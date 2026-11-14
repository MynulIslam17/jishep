/// Build-time switches.
abstract final class FeatureFlags {
  /// Read households from the Overture cells (`cells/{prefix}`): the nearest
  /// homes around the user, with no distance (km) choice. On in every build
  /// (debug, profile, release).
  ///
  /// The old `households` collection (Bangladesh demo data, Settings km
  /// range) is kept only as a fallback:
  ///   flutter run --dart-define=USE_CELL_HOUSEHOLDS=false
  /// Tests may change it (and put back [cellHouseholdsDefault]).
  static bool useCellHouseholds = cellHouseholdsDefault;

  /// The build's value of [useCellHouseholds].
  static const bool cellHouseholdsDefault = bool.fromEnvironment(
    'USE_CELL_HOUSEHOLDS',
    defaultValue: true,
  );
}
