import 'dart:math' as math;

import 'package:cloud_functions/cloud_functions.dart';
import 'package:gps_cielo/core/data/area_search.dart';
import 'package:gps_cielo/core/data/cell_source.dart';
import 'package:gps_cielo/core/data/geo_record.dart';
import 'package:gps_cielo/core/utils/geohash.dart';

/// What the gap-filler added to an area.
enum GapFillStatus {
  /// Not used: flag off, or Overture already had enough homes.
  notNeeded,

  /// Melissa addresses were added.
  added,

  /// Melissa was asked but had nothing (more) nearby.
  noneFound,

  /// The gap-filler could not run; [GapFilledArea.gapMessage] says why.
  failed,
}

/// Calls the `discoverNearby` Cloud Function (Melissa Reverse GeoCoder on
/// the server; keys never reach the app).
class GapFillService {
  GapFillService({
    Future<Map<Object?, Object?>> Function(Map<String, Object?> data)? call,
  }) : _call = call ?? _callFunction;

  final Future<Map<Object?, Object?>> Function(Map<String, Object?> data) _call;

  static Future<Map<Object?, Object?>> _callFunction(
    Map<String, Object?> data,
  ) async {
    final result = await FirebaseFunctions.instanceFor(
      region: 'us-central1',
    ).httpsCallable('discoverNearby').call<Map<Object?, Object?>>(data);
    return result.data;
  }

  /// Up to (50 - [have]) Melissa addresses nearest the point.
  Future<List<GeoRecord>> discover({
    required double latitude,
    required double longitude,
    required int have,
  }) async {
    final data = await _call({
      'latitude': latitude,
      'longitude': longitude,
      'have': have,
    });
    final list = data['records'];
    if (list is! List) return const [];
    return [
      for (final r in list)
        if (r is Map) ?recordFrom(r),
    ];
  }

  /// One backend record as a [GeoRecord] (id `mel:…`), or null if invalid.
  static GeoRecord? recordFrom(Map<Object?, Object?> r) {
    final lat = r['latitude'];
    final lon = r['longitude'];
    final id = r['id']?.toString() ?? '';
    final line = r['line']?.toString().trim() ?? '';
    if (lat is! num || lon is! num || !id.startsWith('mel:') || line.isEmpty) {
      return null;
    }
    String? part(String k) {
      final v = r[k]?.toString().trim() ?? '';
      return v.isEmpty ? null : v;
    }

    final city = part('city');
    final state = part('state');
    final zip = part('zip');
    final cityState = [
      city?.toUpperCase(),
      state?.toUpperCase(),
    ].whereType<String>().join(', ');
    return GeoRecord(
      id: id,
      latitude: lat.toDouble(),
      longitude: lon.toDouble(),
      geohash: Geohash.encode(lat.toDouble(), lon.toDouble(), 9),
      address: line.toUpperCase(),
      cityStateZip: [if (cityState.isNotEmpty) cityState, ?zip].join(' '),
    );
  }

  /// User-facing text for a backend error reason.
  static String messageFor(String? reason) => switch (reason) {
    'user_daily_limit' =>
      "You've looked up extra homes enough times today. Try again tomorrow.",
    'app_daily_limit' ||
    'out_of_credits' => 'Extra home lookups are paused for now.',
    'gap_filler_disabled' => 'Extra home lookups are not turned on yet.',
    'outside_us' => 'Homes are available only in the United States.',
    _ => "Couldn't look up more homes right now.",
  };
}

/// The Overture area, topped up with Melissa addresses when Overture has
/// fewer than [CellArea.maxHouseholds] homes and the gap-filler is on.
///
/// Overture homes always come first in priority: a Melissa address is
/// dropped when it is the same address as an Overture home, or within
/// [duplicateMeters] of one with the same house number. Results are sorted
/// by distance and cut to the nearest 50. Nothing is invented: if both
/// sources together have fewer than 50, the real count is shown.
class GapFilledArea implements AreaSearch {
  GapFilledArea({
    required this.inner,
    required this.service,
    required this.latitude,
    required this.longitude,
  });

  final CellArea inner;
  final GapFillService service;
  final double latitude;
  final double longitude;

  static const double duplicateMeters = 30;

  List<GeoRecord>? _merged;
  Map<String, double> _distances = const {};
  bool _complete = false;
  Future<void>? _loading;

  GapFillStatus gapStatus = GapFillStatus.notNeeded;
  String? gapMessage;

  /// How many of [records] came from Melissa.
  int get melissaCount => records.where((r) => r.id.startsWith('mel:')).length;

  @override
  List<GeoRecord> get records => _merged ?? inner.records;

  @override
  bool get isComplete => _complete;

  @override
  bool get isUnavailable => _complete && records.isEmpty && inner.isUnavailable;

  @override
  double? get extentMeters => _distances.isEmpty
      ? inner.extentMeters
      : _distances.values.reduce(math.max);

  double? distanceOf(String id) => _distances[id] ?? inner.distanceOf(id);

  @override
  bool? contains(String id) =>
      _complete ? records.any((r) => r.id == id) : null;

  @override
  Future<void> ensure(int count) {
    if (_complete) return Future.value();
    return _loading ??= _load().whenComplete(() => _loading = null);
  }

  Future<void> _load() async {
    await inner.ensure(count0);
    final base = inner.records;
    if (base.length >= CellArea.maxHouseholds) {
      _finish(base);
      return;
    }
    List<GeoRecord> extra;
    try {
      extra = await service.discover(
        latitude: latitude,
        longitude: longitude,
        have: base.length,
      );
    } on FirebaseFunctionsException catch (e) {
      gapStatus = GapFillStatus.failed;
      gapMessage = GapFillService.messageFor(e.message);
      _finish(base);
      return;
    } catch (_) {
      gapStatus = GapFillStatus.failed;
      gapMessage = GapFillService.messageFor(null);
      _finish(base);
      return;
    }
    final merged = merge(base, extra, latitude, longitude);
    gapStatus = merged.length > base.length
        ? GapFillStatus.added
        : GapFillStatus.noneFound;
    _finish(merged);
  }

  static const int count0 = CellArea.maxHouseholds;

  void _finish(List<GeoRecord> list) {
    _distances = {
      for (final r in list)
        r.id: haversineMeters(latitude, longitude, r.latitude, r.longitude),
    };
    _merged = list;
    _complete = true;
  }

  static String _norm(String address) =>
      address.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

  static String? _number(String address) =>
      RegExp(r'^\s*(\d+)').firstMatch(address)?.group(1);

  /// Overture first; Melissa addresses that duplicate one are dropped; the
  /// nearest [CellArea.maxHouseholds] are kept, nearest first.
  static List<GeoRecord> merge(
    List<GeoRecord> overture,
    List<GeoRecord> melissa,
    double latitude,
    double longitude,
  ) {
    final seen = {for (final r in overture) _norm(r.address)};
    final kept = [...overture];
    for (final m in melissa) {
      final key = _norm(m.address);
      if (key.isEmpty || seen.contains(key)) continue;
      final number = _number(m.address);
      final near = overture.any(
        (o) =>
            _number(o.address) == number &&
            haversineMeters(o.latitude, o.longitude, m.latitude, m.longitude) <=
                duplicateMeters,
      );
      if (near) continue;
      seen.add(key);
      kept.add(m);
    }
    double d(GeoRecord r) =>
        haversineMeters(latitude, longitude, r.latitude, r.longitude);
    kept.sort((a, b) => d(a).compareTo(d(b)));
    return kept.take(CellArea.maxHouseholds).toList();
  }
}
