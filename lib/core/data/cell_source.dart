import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io' show gzip;
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gps_cielo/core/data/area_search.dart';
import 'package:gps_cielo/core/data/geo_record.dart';
import 'package:gps_cielo/core/utils/geohash.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Household cells from Overture, stored as `cells/{prefix}` (written by
/// tool/overture_cells/seed_firestore.js):
///
///   v: string    Overture release
///   h: Bytes     gzipped JSON `{"v","p","h":[{i,a,o,g,l,c,z}]}`
///   n: int       number of households
///   split: int   only on stubs: the cell is split into children one
///                character longer, each its own document.
///
/// Only `get()` is used (never listeners), and only for prefixes of 5 or
/// more characters.
const String cellsCollection = 'cells';

/// Shortest cell prefix that exists.
const int cellPrecision = 5;

/// One cell document, decoded.
class CellDoc {
  const CellDoc({
    required this.prefix,
    required this.version,
    required this.records,
    this.split,
  });

  final String prefix;
  final String version;

  /// Households in the cell (empty for a stub).
  final List<GeoRecord> records;

  /// Child prefix length when this is a split stub.
  final int? split;

  bool get isStub => split != null;
}

/// Raw access to `cells/{prefix}`; replaced in tests.
abstract class CellReader {
  /// The document from the device cache only (0 reads), or null when the
  /// cache does not hold it.
  Future<Map<String, dynamic>?> fromCache(String prefix);

  /// The document from the server (1 read), or null when it doesn't exist.
  /// Network errors are thrown (and nothing is remembered).
  Future<Map<String, dynamic>?> fromServer(String prefix);
}

/// [CellReader] over Firestore. Firestore's offline persistence keeps every
/// document read from the server on the device, so a cell read once is
/// served from [fromCache] afterwards.
class FirestoreCellReader implements CellReader {
  FirestoreCellReader({FirebaseFirestore? firestore})
    : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  DocumentReference<Map<String, dynamic>> _doc(String prefix) =>
      _db.collection(cellsCollection).doc(prefix);

  @override
  Future<Map<String, dynamic>?> fromCache(String prefix) async {
    try {
      final snap = await _doc(
        prefix,
      ).get(const GetOptions(source: Source.cache));
      return snap.exists ? snap.data() : null;
    } on FirebaseException {
      return null; // not in the cache
    }
  }

  @override
  Future<Map<String, dynamic>?> fromServer(String prefix) async {
    final snap = await _doc(
      prefix,
    ).get(const GetOptions(source: Source.server));
    return snap.exists ? snap.data() : null;
  }
}

/// Remembers cells found missing on the server, so an area without data
/// isn't re-read on every visit. A miss is trusted for [ttl] only: cells
/// are still being seeded, and a missing cell may appear later.
abstract class CellMissCache {
  Future<bool> isFreshMiss(String prefix);
  Future<void> remember(String prefix);
}

/// [CellMissCache] in memory (tests, or when preferences fail).
class MemoryCellMissCache implements CellMissCache {
  MemoryCellMissCache({
    this.ttl = const Duration(days: 1),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final Duration ttl;
  final DateTime Function() _now;
  final Map<String, DateTime> _misses = {};

  @override
  Future<bool> isFreshMiss(String prefix) async {
    final at = _misses[prefix];
    return at != null && _now().difference(at) < ttl;
  }

  @override
  Future<void> remember(String prefix) async => _misses[prefix] = _now();
}

/// [CellMissCache] kept in shared preferences (survives restarts).
class PrefsCellMissCache implements CellMissCache {
  PrefsCellMissCache({this.ttl = const Duration(days: 1)});

  static const String _key = 'cells.misses';
  static const int _maxEntries = 400;

  final Duration ttl;
  Map<String, int>? _misses;

  Future<Map<String, int>> _load() async {
    if (_misses != null) return _misses!;
    final map = <String, int>{};
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final entry in prefs.getStringList(_key) ?? const <String>[]) {
        final i = entry.indexOf(':');
        final at = i > 0 ? int.tryParse(entry.substring(i + 1)) : null;
        if (at != null) map[entry.substring(0, i)] = at;
      }
    } catch (_) {}
    return _misses = map;
  }

  @override
  Future<bool> isFreshMiss(String prefix) async {
    final at = (await _load())[prefix];
    return at != null &&
        DateTime.now().millisecondsSinceEpoch - at < ttl.inMilliseconds;
  }

  @override
  Future<void> remember(String prefix) async {
    final map = await _load();
    final now = DateTime.now().millisecondsSinceEpoch;
    map.removeWhere((_, at) => now - at >= ttl.inMilliseconds);
    map[prefix] = now;
    while (map.length > _maxEntries) {
      map.remove(map.keys.first);
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_key, [
        for (final e in map.entries) '${e.key}:${e.value}',
      ]);
    } catch (_) {}
  }
}

/// Reads made by a [FirestoreCellSource].
class CellReadStats {
  int serverReads = 0;
  int cacheHits = 0;
  int memoryHits = 0;
  int missingCells = 0;
}

/// Loads and decodes cells: memory → device cache → server (1 read).
class FirestoreCellSource {
  FirestoreCellSource({CellReader? reader, CellMissCache? misses})
    : _reader = reader ?? FirestoreCellReader(),
      _misses = misses ?? PrefsCellMissCache();

  final CellReader _reader;
  final CellMissCache _misses;
  final stats = CellReadStats();

  /// Decoded cells kept in memory (a few dozen; each up to 4000 homes).
  static const int _memoryCells = 32;
  final LinkedHashMap<String, CellDoc?> _memory = LinkedHashMap();
  final Map<String, Future<CellDoc?>> _inFlight = {};

  /// Cell [prefix], or null when it doesn't exist (no households there).
  Future<CellDoc?> load(String prefix) {
    if (prefix.length < cellPrecision) {
      throw ArgumentError.value(prefix, 'prefix', 'needs >= $cellPrecision');
    }
    if (_memory.containsKey(prefix)) {
      stats.memoryHits++;
      final doc = _memory.remove(prefix);
      _memory[prefix] = doc; // most recently used
      return Future.value(doc);
    }
    return _inFlight[prefix] ??= _read(prefix).whenComplete(() {
      // (Not `=> remove(...)`: that returns this very future, and
      // whenComplete would wait for itself.)
      _inFlight.remove(prefix);
    });
  }

  Future<CellDoc?> _read(String prefix) async {
    var data = await _reader.fromCache(prefix);
    if (data != null) {
      stats.cacheHits++;
    } else {
      if (await _misses.isFreshMiss(prefix)) {
        stats.missingCells++;
        return _remember(prefix, null);
      }
      stats.serverReads++;
      data = await _reader.fromServer(prefix);
      if (data == null) {
        stats.missingCells++;
        await _misses.remember(prefix);
        return _remember(prefix, null);
      }
    }
    return _remember(prefix, await decodeCellDoc(prefix, data));
  }

  CellDoc? _remember(String prefix, CellDoc? doc) {
    _memory[prefix] = doc;
    while (_memory.length > _memoryCells) {
      _memory.remove(_memory.keys.first);
    }
    return doc;
  }

  /// The nearest households around a point (see [CellArea]).
  CellArea area({required double latitude, required double longitude}) =>
      CellArea(source: this, latitude: latitude, longitude: longitude);
}

/// Decodes a `cells/{prefix}` document. Large cells are unzipped and
/// parsed on a background isolate.
Future<CellDoc> decodeCellDoc(String prefix, Map<String, dynamic> data) async {
  final version = data['v']?.toString() ?? '';
  final split = (data['split'] as num?)?.toInt();
  if (split != null) {
    return CellDoc(
      prefix: prefix,
      version: version,
      records: const [],
      split: split,
    );
  }
  final h = data['h'];
  final Uint8List bytes = h is Blob
      ? h.bytes
      : h is Uint8List
      ? h
      : throw FormatException('cells/$prefix has no h bytes');
  final records = bytes.length > 16 * 1024
      ? await Isolate.run(() => decodeCellRecords(bytes))
      : decodeCellRecords(bytes);
  return CellDoc(prefix: prefix, version: version, records: records);
}

/// Unzips a cell file and reads its households.
List<GeoRecord> decodeCellRecords(Uint8List gz) {
  final json = jsonDecode(utf8.decode(gzip.decode(gz))) as Map<String, dynamic>;
  return [
    for (final h in (json['h'] as List? ?? const []))
      GeoRecord.fromCell((h as Map).cast<String, dynamic>()),
  ];
}

/// The nearest [maxHouseholds] households around a point, from cells.
///
/// Reads the 5-character cell holding the point plus its 8 neighbours
/// (about ±5 km). If they hold fewer than [maxHouseholds] households, it
/// reads the ring around them (5×5 cells) once, and no further. A split
/// cell's children are read nearest-first and only while they can still hold
/// one of the nearest households. Settings' search range is not used.
class CellArea implements AreaSearch {
  CellArea({
    required FirestoreCellSource source,
    required this.latitude,
    required this.longitude,
  }) : _source = source;

  static const int maxHouseholds = 50;

  /// Children of split cells read at once (small, so a dense area doesn't
  /// read children it turns out not to need).
  static const int _parallel = 4;

  final FirestoreCellSource _source;
  final double latitude;
  final double longitude;

  final Map<String, ({GeoRecord record, double meters})> _found = {};
  List<GeoRecord> _records = const [];
  Map<String, double> _nearest = const {};
  bool _complete = false;
  bool _anyCell = false;
  Future<void>? _loading;

  @override
  List<GeoRecord> get records => _records;

  @override
  bool get isComplete => _complete;

  /// True when no cell exists anywhere in the 5×5 block.
  @override
  bool get isUnavailable => _complete && !_anyCell;

  @override
  double? get extentMeters =>
      _nearest.isEmpty ? null : _nearest.values.reduce(math.max);

  /// Distance in meters of a household in the result.
  double? distanceOf(String id) => _nearest[id];

  @override
  bool? contains(String id) => _complete ? _nearest.containsKey(id) : null;

  /// Loads the area once; [count] is ignored (always the nearest
  /// [maxHouseholds]). A failed load can be retried.
  @override
  Future<void> ensure(int count) {
    if (_complete) return Future.value();
    return _loading ??= _load().catchError((Object e, StackTrace s) {
      _loading = null;
      Error.throwWithStackTrace(e, s);
    });
  }

  Future<void> _load() async {
    await _collect(blockCells(latitude, longitude, 1));
    if (_found.length < maxHouseholds) {
      await _collect(blockCells(latitude, longitude, 2, ringOnly: true));
    }
    final sorted = _found.values.toList()
      ..sort((a, b) => a.meters.compareTo(b.meters));
    final nearest = sorted.take(maxHouseholds).toList();
    _records = [for (final f in nearest) f.record];
    _nearest = {for (final f in nearest) f.record.id: f.meters};
    _complete = true;
  }

  /// Reads [cells] (all of them), then split children nearest-first while
  /// they can still be nearer than the [maxHouseholds]th household found.
  Future<void> _collect(List<String> cells) async {
    final pending = <({String prefix, double meters})>[];
    void take(CellDoc? doc) {
      if (doc == null) return;
      _anyCell = true;
      if (doc.isStub) {
        for (final child in Geohash.children(doc.prefix)) {
          pending.add((prefix: child, meters: _cellMeters(child)));
        }
        return;
      }
      for (final r in doc.records) {
        _found.putIfAbsent(
          r.id,
          () => (
            record: r,
            meters: haversineMeters(
              latitude,
              longitude,
              r.latitude,
              r.longitude,
            ),
          ),
        );
      }
    }

    (await Future.wait(cells.map(_source.load))).forEach(take);
    while (pending.isNotEmpty) {
      final bound = _bound();
      pending.sort((a, b) => a.meters.compareTo(b.meters));
      final next = pending
          .where((c) => c.meters <= bound)
          .take(_parallel)
          .toList();
      if (next.isEmpty) break;
      pending.removeWhere(next.contains);
      (await Future.wait(
        next.map((c) => _source.load(c.prefix)),
      )).forEach(take);
    }
  }

  /// Distance of the [maxHouseholds]th nearest household found so far
  /// (infinite while fewer are known).
  double _bound() {
    if (_found.length < maxHouseholds) return double.infinity;
    final d = [for (final f in _found.values) f.meters]..sort();
    return d[maxHouseholds - 1];
  }

  double _cellMeters(String cell) =>
      Geohash.bounds(cell).distanceMetersFrom(latitude, longitude);
}

/// The 5-character cells in a (2r+1)×(2r+1) block centred on the point's
/// cell; with [ringOnly], only the outer ring.
List<String> blockCells(
  double latitude,
  double longitude,
  int r, {
  bool ringOnly = false,
}) {
  final center = Geohash.bounds(
    Geohash.encode(latitude, longitude, cellPrecision),
  );
  final height = center.maxLat - center.minLat;
  final width = center.maxLng - center.minLng;
  final midLat = (center.minLat + center.maxLat) / 2;
  final midLng = (center.minLng + center.maxLng) / 2;
  final cells = <String>{};
  for (var dy = -r; dy <= r; dy++) {
    for (var dx = -r; dx <= r; dx++) {
      if (ringOnly && math.max(dy.abs(), dx.abs()) < r) continue;
      final lat = midLat + dy * height;
      if (lat <= -90 || lat >= 90) continue;
      var lng = midLng + dx * width;
      if (lng > 180) lng -= 360;
      if (lng < -180) lng += 360;
      cells.add(Geohash.encode(lat, lng, cellPrecision));
    }
  }
  return cells.toList();
}
