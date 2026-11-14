import 'package:flutter_test/flutter_test.dart';
import 'package:gps_cielo/core/config/feature_flags.dart';
import 'package:gps_cielo/core/models/user_model.dart';
import 'package:gps_cielo/core/utils/search_range.dart';

void main() {
  test('household counts: 5 to 25, then 50 (the largest)', () {
    expect(SearchRange.options, [5, 10, 15, 20, 25, 50]);
    expect(SearchRange.maxHomes, 50);
    expect(SearchRange.defaultHomes, 50);
  });

  test('normalize snaps stored values to a slider option', () {
    expect(SearchRange.normalize(null), 50);
    expect(SearchRange.normalize(0), 50);
    expect(SearchRange.normalize(-3), 50);
    expect(SearchRange.normalize(1), 5);
    expect(SearchRange.normalize(5), 5);
    expect(SearchRange.normalize(12), 10);
    expect(SearchRange.normalize(13), 15);
    expect(SearchRange.normalize(25), 25);
    expect(SearchRange.normalize(30), 25);
    expect(SearchRange.normalize(40), 50);
    expect(SearchRange.normalize(50), 50);
    expect(SearchRange.normalize(200), 50);
  });

  test('profiles keep a saved count; new profiles get 50', () {
    UserModel read(Object? radius) =>
        UserModel.fromJson({'id': 'alice', 'radiusHomes': ?radius});
    expect(read(10).radiusHomes, 10); // existing users keep theirs
    expect(read(15).radiusHomes, 15);
    expect(read(25).radiusHomes, 25);
    expect(read(50).radiusHomes, 50);
    expect(read(100).radiusHomes, 50);
    expect(read(null).radiusHomes, 50);
    final created = UserModel(id: 'new', fullName: 'N', email: 'n@x.com');
    expect(created.toFirestore()['radiusHomes'], 50);
  });

  test('distances are rounded up so every home is inside', () {
    expect(SearchRange.formatDistance(10), '50 m');
    expect(SearchRange.formatDistance(301), '350 m');
    expect(SearchRange.formatDistance(980), '1 km');
    expect(SearchRange.formatDistance(1000), '1 km');
    expect(SearchRange.formatDistance(1201), '1.3 km');
    expect(SearchRange.formatDistance(8400), '8.4 km');
    expect(SearchRange.formatDistance(14100), '15 km');
  });

  test('farthestMeters ignores homes without a location', () {
    expect(SearchRange.farthestMeters(23.7465, 90.376, const []), isNull);
    expect(
      SearchRange.farthestMeters(23.7465, 90.376, const [
        (latitude: 0.0, longitude: 0.0),
      ]),
      isNull,
    );
    final meters = SearchRange.farthestMeters(23.7465, 90.376, const [
      (latitude: 23.7469, longitude: 90.3768),
      (latitude: 23.7555, longitude: 90.376), // ~1 km north
    ])!;
    expect(meters, closeTo(997, 10));
  });

  test('normalizeKm snaps stored ranges to an offered distance', () {
    expect(SearchRange.normalizeKm(null), 5);
    expect(SearchRange.normalizeKm(0), 5);
    expect(SearchRange.normalizeKm(0.4), 0.5);
    expect(SearchRange.normalizeKm(3), 2);
    expect(SearchRange.normalizeKm(4), 5);
    expect(SearchRange.normalizeKm(100), 20);
  });

  test('profiles without a range use the default', () {
    expect(UserModel.fromJson({'id': 'a'}).searchRadiusKm, 5);
    expect(
      UserModel.fromJson({'id': 'a', 'searchRadiusKm': 10}).searchRadiusKm,
      10,
    );
    expect(
      UserModel(
        id: 'a',
        fullName: '',
        email: '',
        searchRadiusKm: 2,
      ).toFirestore()['searchRadiusKm'],
      2,
    );
  });

  test('labels', () {
    expect(
      SearchRange.label(shown: 10, requested: 10, rangeKm: 5),
      'Nearest 10 homes within 5 km',
    );
    expect(
      SearchRange.label(shown: 3, requested: 10, rangeKm: 0.5),
      '3 homes within 500 m',
    );
    expect(
      SearchRange.label(shown: 1, requested: 10, rangeKm: 1),
      '1 home within 1 km',
    );
    expect(
      SearchRange.label(shown: 0, requested: 10, rangeKm: 2),
      'No homes within 2 km',
    );
    expect(SearchRange.label(shown: 0, requested: 10), 'Nearest 10 homes');
    expect(SearchRange.label(shown: 12, requested: 50), '12 homes nearby');
    expect(SearchRange.neighborhoodSummary(10, 5), '10 homes within 5 km');
  });

  group('with cell households (no km range)', () {
    setUp(() => FeatureFlags.useCellHouseholds = true);
    tearDown(() => FeatureFlags.useCellHouseholds = false);

    test('labels never mention a distance', () {
      expect(SearchRange.userChoosesRange, isFalse);
      expect(
        SearchRange.label(shown: 50, requested: 50, rangeKm: 5),
        'Nearest 50 homes',
      );
      expect(
        SearchRange.label(shown: 12, requested: 50, rangeKm: 5),
        '12 homes nearby',
      );
      expect(
        SearchRange.label(shown: 1, requested: 50, rangeKm: 5),
        '1 home nearby',
      );
      expect(SearchRange.neighborhoodSummary(50, 5), 'Nearest 50 homes');
    });
  });
}
