import 'package:flutter_test/flutter_test.dart';
import 'package:gps_cielo/core/data/geo_search.dart';
import 'package:gps_cielo/core/data/household_repository.dart';
import 'package:gps_cielo/core/utils/geohash.dart';

import 'support/synthetic_households.dart';

void main() {
  group('Geohash', () {
    test('encodes like the stored household hashes', () {
      // Known value for Dhaka (geohash.org): wh0r82…
      expect(Geohash.encode(23.82, 90.36, 4), 'wh0r');
      final box = Geohash.bounds('wh0r');
      expect(box.minLat <= 23.82 && 23.82 <= box.maxLat, isTrue);
      expect(box.minLng <= 90.36 && 90.36 <= box.maxLng, isTrue);
      expect(box.distanceMetersFrom(23.82, 90.36), 0);
    });
  });

  test('fetchCell + GeoSearch on Firestore (fake) match brute force', () async {
    final data = syntheticHouseholds(300, seed: 3);
    final repo = HouseholdRepository(firestore: await seededFirestore(data));
    for (final (lat, lng) in const [(23.7104, 90.4074), (23.75, 90.40)]) {
      final search = GeoSearch(
        query: repo.fetchCell,
        latitude: lat,
        longitude: lng,
        maxMeters: 3000,
        cellLimit: 15, // forces splits and finest-cell paging
      );
      await search.loadAll();
      expect([
        for (final h in search.confirmed) h.doc.id,
      ], bruteForceNearest(data, lat, lng, 3000));
    }
  });

  group('GeoSearch vs brute force', () {
    late List<SyntheticHousehold> data;
    late IndexedHouseholds index;

    setUpAll(() {
      data = syntheticHouseholds(20000, seed: 7);
      index = IndexedHouseholds(data);
    });

    // Dense cluster center, medium cluster, sparse edge, and empty area.
    const centers = [
      (23.7104, 90.4074, 'dense'),
      (23.7460, 90.3760, 'medium'),
      (23.6900, 90.5000, 'sparse'),
      (23.9500, 90.7000, 'empty'),
    ];

    for (final (lat, lng, name) in centers) {
      for (final km in const [0.5, 2.0, 5.0]) {
        test('$name, ${km}km: complete and nearest-first', () async {
          final search = GeoSearch(
            query: index.query,
            latitude: lat,
            longitude: lng,
            maxMeters: km * 1000,
            cellLimit: 40,
          );
          await search.loadAll();
          final expected = bruteForceNearest(data, lat, lng, km * 1000);
          final got = [for (final h in search.confirmed) h.doc.id];
          expect(got, expected); // same households, same order
          expect(got.toSet().length, got.length, reason: 'no duplicates');
          expect(search.isComplete, isTrue);
        });
      }
    }

    test('progressive pages are exact prefixes of the full answer', () async {
      const lat = 23.7286, lng = 90.4182;
      final expected = bruteForceNearest(data, lat, lng, 5000);
      final search = GeoSearch(
        query: index.query,
        latitude: lat,
        longitude: lng,
        maxMeters: 5000,
        cellLimit: 40,
      );
      for (final want in [10, 20, 30, 100, 400]) {
        await search.ensure(want);
        final got = [for (final h in search.confirmed) h.doc.id];
        expect(got.length, greaterThanOrEqualTo(want));
        expect(got, expected.take(got.length).toList());
      }
    });

    test('reads only what the first page needs, and nothing twice', () async {
      const lat = 23.7286, lng = 90.4182;
      final full = GeoSearch(
        query: index.query,
        latitude: lat,
        longitude: lng,
        maxMeters: 5000,
        cellLimit: 40,
      );
      await full.loadAll();

      final paged = GeoSearch(
        query: index.query,
        latitude: lat,
        longitude: lng,
        maxMeters: 5000,
        cellLimit: 40,
      );
      await paged.ensure(10);
      expect(paged.stats.documents, lessThan(full.stats.documents ~/ 5));

      // Reading the rest progressively costs about the same as all at once.
      await paged.loadAll();
      expect(paged.confirmed.length, full.confirmed.length);
      expect(paged.stats.documents, lessThan(full.stats.documents * 1.5));
    });
  });
}
