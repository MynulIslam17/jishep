import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:gps_cielo/core/config/feature_flags.dart';
import 'package:gps_cielo/core/data/cell_source.dart';
import 'package:gps_cielo/core/models/user_model.dart';
import 'package:gps_cielo/core/services/household_store.dart';
import 'package:gps_cielo/core/utils/geohash.dart';

import 'support/fake_cell_reader.dart';
import 'support/fake_household_repository.dart';

// Spring Valley, CA.
const _lat = 32.7448;
const _lng = -116.9989;

UserModel _user({int radiusHomes = 10, double rangeKm = 1}) => UserModel(
  id: 'alice',
  fullName: 'Test',
  email: 'alice@example.com',
  address: '3510 Helix St, Spring Valley, CA',
  latitude: _lat,
  longitude: _lng,
  radiusHomes: radiusHomes,
  searchRadiusKm: rangeKm,
);

/// [count] homes going north, 0.0002° (~22 m) apart: the 50th is ~1.1 km
/// away, beyond a 1 km Settings range.
List<CellHome> _homes(int count) => [
  for (var i = 0; i < count; i++)
    (id: 'h$i', lat: _lat + 0.0002 * (i + 1), lng: _lng),
];

void main() {
  late FakeHouseholdRepository repository;
  late FakeCellReader reader;
  late HouseholdStore store;

  setUp(() {
    Get.testMode = true;
    FeatureFlags.useCellHouseholds = true;
    reader = FakeCellReader();
    repository = FakeHouseholdRepository()
      ..cells = FirestoreCellSource(
        reader: reader,
        misses: MemoryCellMissCache(),
      );
    store = HouseholdStore(repository, FakeNotificationRepository());
  });

  tearDown(() => FeatureFlags.useCellHouseholds = false);

  test('households come from the cells, nearest first, up to 50', () async {
    reader.seed(_homes(120));
    await store.bindUser(_user());

    expect(repository.fetches, isEmpty, reason: 'no households reads');
    expect(repository.cellFetches, isNotEmpty);
    expect(store.households.map((h) => h.id), [
      for (var i = 0; i < 10; i++) 'h$i',
    ]);
    // The Settings range (1 km) is not used: all 50 nearest, ~1.1 km out.
    expect(store.areaHouseholds, hasLength(50));
    expect(store.areaComplete.value, isTrue);
    expect(store.areaUnavailable.value, isFalse);
    expect(store.homeHouseholds, hasLength(10));
    expect(store.rangeMeters.value, greaterThan(1000));

    final h = store.households.first;
    expect(h.address, 'H0 HELIX ST');
    expect(h.cityStateZip, 'SPRING VALLEY, CA 91977');
    expect(h.latitude, closeTo(_lat + 0.0002, 1e-9));
  });

  test('changing the Home count 5 → 25 reads nothing', () async {
    reader.seed(_homes(120));
    await store.bindUser(_user());
    final reads = reader.serverReads.length;

    await store.filterRadius(5);
    expect(store.households, hasLength(5));
    await store.filterRadius(25);
    expect(store.households, hasLength(25));
    expect(reader.serverReads, hasLength(reads));
  });

  test('status flags merge by household id', () async {
    reader.seed(_homes(60));
    repository.serverStatuses['alice'] = {
      'h1': {'isPrayed': true, 'prayedAt': Timestamp.now()},
      'h2': {'hasFollowUp': true, 'followUpDate': '2026-11-20'},
    };
    await store.bindUser(_user());

    final byId = {for (final h in store.households) h.id: h};
    expect(byId['h1']!.isPrayed, isTrue);
    expect(byId['h2']!.hasFollowUp, isTrue);
    expect(byId['h0']!.isPrayed, isFalse);
  });

  test('no cells around the point: area unavailable', () async {
    await store.bindUser(_user());

    expect(store.households, isEmpty);
    expect(store.areaComplete.value, isTrue);
    expect(store.areaUnavailable.value, isTrue);
    expect(store.homeUnavailable.value, isTrue);
  });

  test('a cell elsewhere is not "unavailable", just few homes', () async {
    // One home two cells north (in the 5x5 ring only).
    final cell = Geohash.bounds(Geohash.encode(_lat, _lng, 5));
    final h = cell.maxLat - cell.minLat;
    reader.seed([
      (
        id: 'far',
        lat: (cell.minLat + cell.maxLat) / 2 + 2 * h,
        lng: (cell.minLng + cell.maxLng) / 2,
      ),
    ]);
    await store.bindUser(_user());

    expect(store.areaUnavailable.value, isFalse);
    expect(store.households.map((h) => h.id), ['far']);
  });
}
