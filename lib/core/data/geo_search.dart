import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gps_cielo/core/utils/geohash.dart';

typedef GeoDoc = DocumentSnapshot<Map<String, dynamic>>;

/// Reads households whose geohash starts with [prefix], in geohash order,
/// at most [limit], after [startAfter] when given.
typedef GeoCellQuery =
    Future<List<GeoDoc>> Function(
      String prefix, {
      required int limit,
      GeoDoc? startAfter,
    });

/// A household found by [GeoSearch], with its distance from the center.
class GeoHit {
  const GeoHit(this.doc, this.meters);

  final GeoDoc doc;
  final double meters;
}

/// Reads made by a [GeoSearch]; Firestore bills one read per document
/// returned and one per query that returns nothing.
class GeoSearchStats {
  int queries = 0;
  int documents = 0;

  int emptyQueries = 0;

  /// Sequential network round trips (queries in one circle run in parallel).
  int roundTrips = 0;

  int get billedReads => documents + emptyQueries;
}

/// Progressive, nearest-first search for households around a point.
///
/// Firestore cannot sort by distance, so the search works outwards in
/// circles: it reads every household inside a circle (via geohash cells),
/// and only then treats them as complete. [confirmed] holds the households
/// within [coveredMeters], in exact distance order — nothing nearer can be
/// missing. [ensure] widens the circle (doubling, up to [maxMeters]) only
/// when more households are needed, so a screen that shows 10 reads about
/// 10, not the whole range.
///
/// No document is read twice: fully read cells are remembered, and a wider
/// circle only queries the cells it has not read yet. A cell holding more
/// than [cellLimit] households is split into its 32 sub-cells (skipping those
/// outside the circle); at the finest precision it is paged with a cursor.
class GeoSearch {
  GeoSearch({
    required this.query,
    required this.latitude,
    required this.longitude,
    required this.maxMeters,
    this.startMeters = 20,
    this.cellLimit = 60,
    this.coverCellRatio = 1.0,
  }) : assert(maxMeters > 0),
       assert(cellLimit > 0);

  final GeoCellQuery query;
  final double latitude;
  final double longitude;
  final double maxMeters;
  final double startMeters;
  final int cellLimit;
  final double coverCellRatio;

  final stats = GeoSearchStats();

  final Map<String, GeoHit> _found = {};
  final Set<String> _loadedCells = {};

  /// Cells read partway (a dense cell's sub-cell outside the circle so
  /// far), with the last document read, so reading resumes there.
  final Map<String, GeoDoc> _partial = {};
  double _covered = 0;
  List<GeoHit>? _confirmedCache;

  /// Radius around the center within which every household is known.
  double get coveredMeters => _covered;

  /// True once the whole range has been read.
  bool get isComplete => _covered >= maxMeters;

  /// Households within [coveredMeters] (and the range), nearest first.
  List<GeoHit> get confirmed {
    return _confirmedCache ??= [
      for (final hit in _found.values)
        if (hit.meters <= _covered && hit.meters <= maxMeters) hit,
    ]..sort((a, b) => a.meters.compareTo(b.meters));
  }

  /// Distance of a household already read (inside the circle or not).
  double? distanceOf(String id) => _found[id]?.meters;

  /// Widens the search until at least [count] households are confirmed or
  /// the whole range is read.
  Future<void> ensure(int count) async {
    while (confirmed.length < count && !isComplete) {
      await _cover(math.min(_nextRadius(count), maxMeters));
    }
  }

  /// The next circle: households grow with the area (radius squared), so
  /// size it from the density seen so far — small steps in dense areas
  /// (read little), big steps where it is sparse (few empty queries).
  double _nextRadius(int wanted) {
    if (_covered == 0) return startMeters;
    final have = confirmed.length;
    final factor = have == 0
        ? 4.0
        : (math.sqrt(wanted / have) * 1.15).clamp(1.25, 4.0);
    return _covered * factor;
  }

  /// Reads the whole range.
  Future<void> loadAll() => ensure(1 << 30);

  Future<void> _cover(double radius) async {
    // Cells are disjoint, so they are read in parallel; the round trips are
    // the longest chain of dependent queries.
    final depths = await Future.wait([
      for (final cell in _coverCells(radius)) _loadCell(cell, radius),
    ]);
    stats.roundTrips += depths.fold(0, math.max);
    _covered = radius;
    _confirmedCache = null;
  }

  /// Cells touching the circle, at a precision whose cells are at least
  /// [coverCellRatio] × [radius] (finer cells read less outside the circle,
  /// at the cost of more, often empty, queries).
  List<String> _coverCells(double radius) {
    final minSize = radius * coverCellRatio;
    var precision = 1;
    while (precision < Geohash.maxPrecision) {
      final size = Geohash.cellSize(precision + 1, latitude);
      if (math.min(size.height, size.width) < minSize) break;
      precision++;
    }
    final size = Geohash.cellSize(precision, latitude);
    final dLat = size.height / 111320;
    final dLng =
        size.width / (111320 * math.cos(latitude * math.pi / 180)).abs();
    final reachLat = radius / 111320;
    final reachLng =
        radius / (111320 * math.cos(latitude * math.pi / 180)).abs();
    final steps = (reachLat / dLat).ceil();
    final stepsLng = (reachLng / dLng).ceil();
    final cells = <String>{};
    for (var i = -steps; i <= steps; i++) {
      for (var j = -stepsLng; j <= stepsLng; j++) {
        final lat = (latitude + i * dLat).clamp(-89.999999, 89.999999);
        var lng = longitude + j * dLng;
        if (lng > 180) lng -= 360;
        if (lng < -180) lng += 360;
        cells.add(Geohash.encode(lat.toDouble(), lng, precision));
      }
    }
    final touching = [
      for (final c in cells)
        if (_touches(c, radius)) c,
    ];
    // Nearest cells first.
    touching.sort(
      (a, b) => Geohash.bounds(a)
          .distanceMetersFrom(latitude, longitude)
          .compareTo(Geohash.bounds(b).distanceMetersFrom(latitude, longitude)),
    );
    return touching;
  }

  bool _touches(String cell, double radius) =>
      Geohash.bounds(cell).distanceMetersFrom(latitude, longitude) <= radius;

  bool _isLoaded(String cell) {
    for (var i = 1; i <= cell.length; i++) {
      if (_loadedCells.contains(cell.substring(0, i))) return true;
    }
    return false;
  }

  bool _hasLoadedInside(String cell) =>
      _loadedCells.any((c) => c.length > cell.length && c.startsWith(cell)) ||
      _partial.keys.any((c) => c.length > cell.length && c.startsWith(cell));

  /// Reads [cell] (from after [after], when part of it is already read).
  /// Returns the number of sequential queries it took.
  Future<int> _loadCell(String cell, double radius, {GeoDoc? after}) async {
    if (_isLoaded(cell)) return 0;
    after ??= _partial[cell];
    if (!_touches(cell, radius)) {
      // Not needed yet; remember how far it was read.
      if (after != null) _partial[cell] = after;
      return 0;
    }
    _partial.remove(cell);
    if (after == null &&
        _hasLoadedInside(cell) &&
        cell.length < Geohash.maxPrecision) {
      // Part of it was read for a smaller circle: read only the rest.
      final depths = await Future.wait([
        for (final child in Geohash.children(cell)) _loadCell(child, radius),
      ]);
      return depths.fold<int>(0, math.max);
    }

    if (cell.length >= Geohash.maxPrecision) {
      return _pageCell(cell, after);
    }

    final docs = await _run(cell, limit: cellLimit + 1, startAfter: after);
    _add(docs);
    if (docs.length <= cellLimit) {
      _loadedCells.add(cell);
      return 1;
    }

    // Dense cell. Results come in geohash order, so the sub-cells before the
    // last returned document are complete, the one holding it continues
    // from it, and later ones are read only if they touch the circle.
    final last = docs.last;
    final lastHash = _hashOf(last);
    final pending = <Future<int>>[];
    for (final child in Geohash.children(cell)) {
      if (lastHash.startsWith(child)) {
        pending.add(_loadCell(child, radius, after: last));
      } else if (child.compareTo(lastHash) < 0) {
        _loadedCells.add(child);
      } else {
        pending.add(_loadCell(child, radius));
      }
    }
    final depths = await Future.wait(pending);
    return 1 + depths.fold<int>(0, math.max);
  }

  /// Reads a finest-precision cell completely, page by page.
  Future<int> _pageCell(String cell, GeoDoc? after) async {
    GeoDoc? cursor = after;
    var trips = 0;
    while (true) {
      final docs = await _run(cell, limit: cellLimit, startAfter: cursor);
      trips++;
      _add(docs);
      if (docs.length < cellLimit) break;
      cursor = docs.last;
    }
    _loadedCells.add(cell);
    return trips;
  }

  Future<List<GeoDoc>> _run(
    String cell, {
    required int limit,
    GeoDoc? startAfter,
  }) async {
    final docs = await query(cell, limit: limit, startAfter: startAfter);
    stats.queries++;
    stats.documents += docs.length;
    if (docs.isEmpty) stats.emptyQueries++;
    return docs;
  }

  void _add(List<GeoDoc> docs) {
    for (final doc in docs) {
      if (_found.containsKey(doc.id)) continue;
      final point = _pointOf(doc);
      if (point == null) continue;
      _found[doc.id] = GeoHit(
        doc,
        haversineMeters(latitude, longitude, point.latitude, point.longitude),
      );
    }
    _confirmedCache = null;
  }

  static String _hashOf(GeoDoc doc) {
    final geo = doc.data()?['geo'];
    final hash = geo is Map ? geo['geohash'] : null;
    return hash is String ? hash : '';
  }

  static GeoPoint? _pointOf(GeoDoc doc) {
    final geo = doc.data()?['geo'];
    final point = geo is Map ? geo['geopoint'] : null;
    return point is GeoPoint ? point : null;
  }
}
