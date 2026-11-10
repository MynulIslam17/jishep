import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

/// Search preferences (Settings > My preferences):
///  * the search **range** — households are searched within this distance
///    of the search center (`users/{uid}.searchRadiusKm`);
///  * the **number of households** to show, nearest first
///    (`users/{uid}.radiusHomes`, the default for the Home filter).
abstract final class SearchRange {
  /// Household counts offered (Settings default and Home filter).
  static const List<int> options = [5, 10, 15, 20, 25];
  static const int defaultHomes = 10;

  /// The largest number of households the Home filter can show.
  static int get maxHomes => options.last;

  /// At most this many households are loaded per search (nearest first).
  /// The Home filter shows the nearest few; Neighborhood pages through all.
  static const int maxInRange = 200;

  /// Search ranges offered, in kilometres.
  static const List<double> distanceOptionsKm = [0.5, 1, 2, 5, 10, 20];
  static const double defaultKm = 5;

  /// Snaps any stored count (missing, old or out of range) to an option.
  static int normalize(int? homes) {
    if (homes == null || homes <= 0) return defaultHomes;
    return options.reduce(
      (best, option) =>
          (option - homes).abs() < (best - homes).abs() ? option : best,
    );
  }

  /// Snaps any stored range to an offered distance.
  static double normalizeKm(num? km) {
    if (km == null || km <= 0) return defaultKm;
    return distanceOptionsKm.reduce(
      (best, option) => (option - km).abs() < (best - km).abs() ? option : best,
    );
  }

  /// Distance in meters from the center to the farthest of [points], or
  /// null when there are none. Points at (0, 0) have no location.
  static double? farthestMeters(
    double centerLatitude,
    double centerLongitude,
    Iterable<({double latitude, double longitude})> points,
  ) {
    const distance = Distance();
    final center = LatLng(centerLatitude, centerLongitude);
    double? farthest;
    for (final p in points) {
      if (p.latitude == 0 && p.longitude == 0) continue;
      final meters = distance.as(
        LengthUnit.Meter,
        center,
        LatLng(p.latitude, p.longitude),
      );
      farthest = math.max(farthest ?? 0, meters);
    }
    return farthest;
  }

  /// "500 m", "1 km", "1.5 km", "14 km" — rounded up.
  static String formatDistance(double meters) {
    if (meters < 1000) {
      final rounded = math.max(50, (meters / 50).ceil() * 50);
      return rounded >= 1000 ? '1 km' : '$rounded m';
    }
    final km = meters / 1000;
    if (km < 10) {
      final tenths = (km * 10).ceil() / 10;
      return tenths == tenths.roundToDouble()
          ? '${tenths.toInt()} km'
          : '${tenths.toStringAsFixed(1)} km';
    }
    return '${km.ceil()} km';
  }

  static String formatKm(double km) => formatDistance(km * 1000);

  /// "Nearest 10 homes within 5 km", "3 homes within 5 km" when fewer
  /// exist, "No homes within 5 km". Without a range: "Nearest 10 homes".
  static String label({
    required int shown,
    required int requested,
    double? rangeKm,
  }) {
    if (rangeKm == null) return 'Nearest $requested homes';
    final within = 'within ${formatKm(rangeKm)}';
    if (shown == 0) return 'No homes $within';
    if (shown < requested) {
      return '$shown ${shown == 1 ? 'home' : 'homes'} $within';
    }
    return 'Nearest $shown homes $within';
  }
}
