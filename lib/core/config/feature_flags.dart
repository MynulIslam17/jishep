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

  /// "Check address" in the household sheet (Melissa, through the
  /// `enrichHousehold` Cloud Function). Off until that function and its
  /// Melissa secret are deployed:
  ///   flutter run --dart-define=ADDRESS_CHECKS=true
  static bool addressChecks = const bool.fromEnvironment(
    'ADDRESS_CHECKS',
    defaultValue: false,
  );

  /// Top up areas where Overture has fewer than 50 homes with Melissa
  /// Reverse GeoCoder addresses (`discoverNearby` Cloud Function; costs
  /// Melissa credits). Off until production spending is approved:
  ///   flutter run --dart-define=MELISSA_GAP_FILL=true
  /// The server has its own switch (MELISSA_GAP_FILL_ENABLED) as well.
  static bool melissaGapFill = const bool.fromEnvironment(
    'MELISSA_GAP_FILL',
    defaultValue: false,
  );

  /// Recorded owner names on the neighborhood homes, from the owner
  /// records already stored on the server (`discoverOwners`, cache only
  /// while the server's paid discovery is off). Homes without a stored
  /// record keep their address. On by default; off with:
  ///   flutter run --dart-define=MELISSA_OWNERS=false
  /// The server decides whether names are served (MELISSA_ALLOW_OWNER_NAMES).
  static bool melissaOwners = const bool.fromEnvironment(
    'MELISSA_OWNERS',
    defaultValue: true,
  );
}
