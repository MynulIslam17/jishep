import 'dart:math' as math;

import 'package:gps_cielo/core/config/feature_flags.dart';
import 'package:latlong2/latlong.dart';

/// Search preferences (Settings > Prayer preferences):
///  * the **number of households** in "my neighborhood", nearest first
///    (`users/{uid}.radiusHomes`, also the default for the Home filter);
///  * the search **range** — households are searched within this distance
///    of the search center (`users/{uid}.searchRadiusKm`). Only with the
///    `households` collection: with `FeatureFlags.useCellHouseholds` the
///    neighborhood is simply the nearest homes and no range is shown
///    ([userChoosesRange]).
abstract final class SearchRange {
  /// Household counts offered (Settings default and Home filter).
  static const List<int> options = [5, 10, 15, 20, 25, 50];

  /// The neighborhood size given to new accounts, and used when a stored
  /// count is missing. Existing accounts keep their saved `radiusHomes`.
  static const int defaultHomes = 50;

  /// Whether the user picks a search range in km. False with cell
  /// households: the neighborhood is "the nearest N homes", and the range
  /// is neither offered in Settings nor shown in labels.
  static bool get userChoosesRange => !FeatureFlags.useCellHouseholds;

  /// "Nearest 50 homes", or "10 homes within 5 km" when the user picks a
  /// range (Profile summary and the save confirmation).
  static String neighborhoodSummary(int homes, double rangeKm) =>
      userChoosesRange
      ? '$homes homes within ${formatKm(rangeKm)}'
      : 'Nearest $homes homes';

  /// Daily prayer goals offered (Settings > Prayer preferences).
  static const List<int> goalOptions = [3, 5, 10, 15];

  /// A daily goal can never be more than the homes in the neighborhood
  /// (you cannot pray for 15 different neighbors a day among 10). Returns
  /// [goal], or the largest goal option that fits in [homes].
  static int clampGoal(int goal, int homes) {
    if (goal <= homes) return goal;
    final fitting = goalOptions.where((g) => g <= homes);
    return fitting.isEmpty ? goalOptions.first : fitting.last;
  }

  /// The largest number of households the Home filter can show.
  static int get maxHomes => options.last;

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

  /// Meters between two points, or null when either has no location (0, 0).
  static double? distanceMeters(
    double fromLatitude,
    double fromLongitude,
    double toLatitude,
    double toLongitude,
  ) {
    if ((fromLatitude == 0 && fromLongitude == 0) ||
        (toLatitude == 0 && toLongitude == 0)) {
      return null;
    }
    return const Distance().as(
      LengthUnit.Meter,
      LatLng(fromLatitude, fromLongitude),
      LatLng(toLatitude, toLongitude),
    );
  }

  /// How far a home is: "30 m", "450 m", "1.2 km", "14 km".
  static String formatHomeDistance(double meters) {
    final rounded = math.max(10, (meters / 10).round() * 10);
    if (rounded < 1000) return '$rounded m';
    final km = meters / 1000;
    return km < 10 ? '${km.toStringAsFixed(1)} km' : '${km.round()} km';
  }

  /// "Nearest 10 homes within 5 km", "3 homes within 5 km" when fewer
  /// exist, "No homes within 5 km". Without a range (unknown yet, or not
  /// chosen by the user — see [userChoosesRange]): "Nearest 10 homes", or
  /// "3 homes nearby" when fewer exist.
  static String label({
    required int shown,
    required int requested,
    double? rangeKm,
  }) {
    if (!userChoosesRange) rangeKm = null;
    if (rangeKm == null) {
      if (shown > 0 && shown < requested) {
        return '$shown ${shown == 1 ? 'home' : 'homes'} nearby';
      }
      return 'Nearest $requested homes';
    }
    final within = 'within ${formatKm(rangeKm)}';
    if (shown == 0) return 'No homes $within';
    if (shown < requested) {
      return '$shown ${shown == 1 ? 'home' : 'homes'} $within';
    }
    return 'Nearest $shown homes $within';
  }
}
