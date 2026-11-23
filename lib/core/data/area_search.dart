import 'package:gps_cielo/core/data/geo_record.dart';
import 'package:gps_cielo/core/data/geo_search.dart';

/// Households around a point, nearest first, as [HouseholdStore] uses them.
/// Implemented by [GeoSearchArea] (the `households` collection) and
/// `CellArea` (Overture cells).
abstract class AreaSearch {
  /// Households known to be in the area so far, nearest first.
  List<GeoRecord> get records;

  /// True once nothing more will be found.
  bool get isComplete;

  /// True when no data exists for this area at all (not "0 households").
  bool get isUnavailable => false;

  /// Distance to show as the area's extent, or null to use the Settings
  /// range.
  double? get extentMeters => null;

  /// Reads until at least [count] households are known or the area is
  /// complete.
  Future<void> ensure(int count);

  /// Whether household [id] is in the area: true/false when known, null
  /// when not read far enough to tell.
  bool? contains(String id);
}

/// The progressive `households` search, as an [AreaSearch].
class GeoSearchArea implements AreaSearch {
  GeoSearchArea(this.search);

  final GeoSearch search;
  final Map<String, GeoRecord> _records = {};

  @override
  List<GeoRecord> get records => [
    for (final hit in search.confirmed)
      _records.putIfAbsent(hit.doc.id, () => GeoRecord.fromSnapshot(hit.doc)),
  ];

  @override
  bool get isComplete => search.isComplete;

  @override
  bool get isUnavailable => false;

  @override
  double? get extentMeters => null;

  @override
  Future<void> ensure(int count) => search.ensure(count);

  @override
  bool? contains(String id) {
    final meters = search.distanceOf(id);
    if (meters != null) return meters <= search.maxMeters;
    return search.isComplete ? false : null;
  }
}
