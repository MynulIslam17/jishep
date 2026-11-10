import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:gps_cielo/core/utils/geohash.dart';

/// A synthetic household for tests and benchmarks.
typedef SyntheticHousehold = ({String id, double lat, double lng});

/// Deterministic Dhaka-area households: a few very dense clusters (old city
/// blocks), medium clusters and a sparse scatter, like `tool/seed_scale`.
List<SyntheticHousehold> syntheticHouseholds(int count, {int seed = 42}) {
  final rnd = math.Random(seed);
  const dense = [(23.7104, 90.4074), (23.7286, 90.4182)];
  const medium = [(23.7460, 90.3760), (23.7808, 90.4067), (23.7210, 90.4830)];
  double gauss() {
    final u = 1 - rnd.nextDouble(), v = rnd.nextDouble();
    return math.sqrt(-2 * math.log(u)) * math.cos(2 * math.pi * v);
  }

  final out = <SyntheticHousehold>[];
  for (var i = 0; i < count; i++) {
    final r = rnd.nextDouble();
    double lat, lng;
    if (r < 0.4) {
      final c = dense[rnd.nextInt(dense.length)];
      lat = c.$1 + gauss() * 0.0015; // ~170 m
      lng = c.$2 + gauss() * 0.0015;
    } else if (r < 0.8) {
      final c = medium[rnd.nextInt(medium.length)];
      lat = c.$1 + gauss() * 0.006; // ~650 m
      lng = c.$2 + gauss() * 0.006;
    } else {
      lat = 23.68 + rnd.nextDouble() * 0.16; // ~18 km box
      lng = 90.33 + rnd.nextDouble() * 0.18;
    }
    out.add((id: 'syn_${i.toString().padLeft(6, '0')}', lat: lat, lng: lng));
  }
  return out;
}

Future<FakeFirebaseFirestore> seededFirestore(
  List<SyntheticHousehold> households,
) async {
  final db = FakeFirebaseFirestore();
  for (final h in households) {
    await db.collection('households').doc(h.id).set({
      'residentName': 'Test Household ${h.id}',
      'address': '(synthetic)',
      'isTest': true,
      'geo': {
        'geohash': Geohash.encode(h.lat, h.lng, 10),
        'geopoint': GeoPoint(h.lat, h.lng),
      },
    });
  }
  return db;
}

/// Exact answer: ids within [meters] of the point, nearest first.
List<String> bruteForceNearest(
  List<SyntheticHousehold> households,
  double lat,
  double lng,
  double meters,
) {
  final within = [
    for (final h in households)
      (id: h.id, d: haversineMeters(lat, lng, h.lat, h.lng)),
  ].where((e) => e.d <= meters).toList()..sort((a, b) => a.d.compareTo(b.d));
  return [for (final e in within) e.id];
}

// ignore: subtype_of_sealed_class
class _Doc implements DocumentSnapshot<Map<String, dynamic>> {
  _Doc(this.id, this.hash, this._data);

  @override
  final String id;
  final String hash;
  final Map<String, dynamic> _data;

  @override
  Map<String, dynamic> data() => _data;

  @override
  bool get exists => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// In-memory model of the Firestore cell query
/// `orderBy('geo.geohash').startAt([p]).endAt(['p~']).limit(n)` (with
/// `startAfterDocument`), using a sorted index like Firestore's. Lets
/// correctness and read-count tests run at 100k households in seconds.
/// Counts every query and returned document, as Firestore bills them.
class IndexedHouseholds {
  IndexedHouseholds(
    List<SyntheticHousehold> households, {
    Map<String, dynamic> Function(SyntheticHousehold h)? fields,
  }) : _docs = [
         for (final h in households)
           _Doc(h.id, Geohash.encode(h.lat, h.lng, 10), {
             'residentName': 'Test Household ${h.id}',
             'address': '(synthetic)',
             ...?fields?.call(h),
             'geo': {
               'geohash': Geohash.encode(h.lat, h.lng, 10),
               'geopoint': GeoPoint(h.lat, h.lng),
             },
           }),
       ]..sort(_compare);

  final List<_Doc> _docs;
  int queries = 0;
  int documentsRead = 0;
  int emptyQueries = 0;

  int get billedReads => documentsRead + emptyQueries;

  static int _compare(_Doc a, _Doc b) {
    final c = a.hash.compareTo(b.hash);
    return c != 0 ? c : a.id.compareTo(b.id);
  }

  int _lowerBound(bool Function(_Doc) isBefore) {
    var lo = 0, hi = _docs.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (isBefore(_docs[mid])) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  Future<List<DocumentSnapshot<Map<String, dynamic>>>> query(
    String prefix, {
    required int limit,
    DocumentSnapshot<Map<String, dynamic>>? startAfter,
  }) async {
    final after = startAfter as _Doc?;
    final start = after == null
        ? _lowerBound((d) => d.hash.compareTo(prefix) < 0)
        : _lowerBound((d) => _compare(d, after) <= 0);
    final end = '$prefix~';
    final out = <_Doc>[];
    for (var i = start; i < _docs.length && out.length < limit; i++) {
      if (_docs[i].hash.compareTo(end) > 0) break;
      out.add(_docs[i]);
    }
    queries++;
    documentsRead += out.length;
    if (out.isEmpty) emptyQueries++;
    return out;
  }

  /// What the old geoflutterfire `fetchWithin` reads, as billed: every
  /// document in the center cell and its 8 neighbors at its precision.
  int legacyReads(double lat, double lng, double radiusKm, int precision) {
    final cells = <String>{};
    final size = Geohash.cellSize(precision, lat);
    final dLat = size.height / 111320;
    final dLng = size.width / (111320 * math.cos(lat * math.pi / 180));
    for (final i in const [-1, 0, 1]) {
      for (final j in const [-1, 0, 1]) {
        cells.add(Geohash.encode(lat + i * dLat, lng + j * dLng, precision));
      }
    }
    var billed = 0;
    for (final c in cells) {
      final from = _lowerBound((d) => d.hash.compareTo(c) < 0);
      final to = _lowerBound((d) => d.hash.compareTo('$c~') <= 0);
      final n = to - from;
      billed += n == 0 ? 1 : n;
    }
    return billed;
  }
}
