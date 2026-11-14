/// Build-time switches.
abstract final class FeatureFlags {
  /// Read households from the Overture cells (`cells/{prefix}`) instead of
  /// the `households` collection. Off until verified on a device:
  ///   flutter run --dart-define=USE_CELL_HOUSEHOLDS=true
  /// Tests may change it.
  static bool useCellHouseholds = const bool.fromEnvironment(
    'USE_CELL_HOUSEHOLDS',
  );
}
