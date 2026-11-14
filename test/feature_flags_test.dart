import 'package:flutter_test/flutter_test.dart';
import 'package:gps_cielo/core/config/feature_flags.dart';
import 'package:gps_cielo/core/utils/search_range.dart';

void main() {
  test('cell households (Overture) are on by default, with no km choice', () {
    // Holds for every build made without --dart-define=USE_CELL_HOUSEHOLDS.
    expect(FeatureFlags.cellHouseholdsDefault, isTrue);
    expect(FeatureFlags.useCellHouseholds, isTrue);
    expect(SearchRange.userChoosesRange, isFalse);
    expect(SearchRange.defaultHomes, 50);
  });

  test('home distances read naturally', () {
    expect(SearchRange.formatHomeDistance(4), '10 m');
    expect(SearchRange.formatHomeDistance(33), '30 m');
    expect(SearchRange.formatHomeDistance(996), '1.0 km');
    expect(SearchRange.formatHomeDistance(1234), '1.2 km');
    expect(SearchRange.formatHomeDistance(14400), '14 km');
    expect(SearchRange.distanceMeters(0, 0, 32.7, -117), isNull);
    expect(
      SearchRange.distanceMeters(32.7448, -116.9989, 32.7457, -116.9989),
      closeTo(100, 1),
    );
  });
}
