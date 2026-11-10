import 'package:flutter_test/flutter_test.dart';
import 'package:gps_cielo/core/models/user_model.dart';
import 'package:gps_cielo/core/utils/search_range.dart';

void main() {
  test('normalize snaps stored values to a slider option', () {
    expect(SearchRange.normalize(null), 10);
    expect(SearchRange.normalize(0), 10);
    expect(SearchRange.normalize(-3), 10);
    expect(SearchRange.normalize(1), 5);
    expect(SearchRange.normalize(5), 5);
    expect(SearchRange.normalize(12), 10);
    expect(SearchRange.normalize(13), 15);
    expect(SearchRange.normalize(25), 25);
    expect(SearchRange.normalize(50), 25);
  });

  test('profiles read an out-of-range radius as a valid option', () {
    UserModel read(Object? radius) =>
        UserModel.fromJson({'id': 'alice', 'radiusHomes': ?radius});
    expect(read(null).radiusHomes, 10);
    expect(read(50).radiusHomes, 25);
    expect(read(15).radiusHomes, 15);
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
  });
}
