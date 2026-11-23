import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gps_cielo/core/data/cell_source.dart';
import 'package:gps_cielo/core/utils/geohash.dart';

import 'support/fake_cell_reader.dart';

// Spring Valley, CA.
const _lat = 32.7448;
const _lng = -116.9989;

typedef _Home = CellHome;
const _release = cellRelease;

/// [count] homes going north from the center, [step] degrees apart
/// (0.0001° ≈ 11 m).
List<_Home> _north(int count, {double step = 0.0001, String id = 'h'}) => [
  for (var i = 0; i < count; i++)
    (id: '$id$i', lat: _lat + step * (i + 1), lng: _lng),
];

List<String> _nearestIds(List<_Home> homes, int n) {
  final sorted = [...homes]
    ..sort(
      (a, b) => haversineMeters(
        _lat,
        _lng,
        a.lat,
        a.lng,
      ).compareTo(haversineMeters(_lat, _lng, b.lat, b.lng)),
    );
  return [for (final h in sorted.take(n)) h.id];
}

void main() {
  late FakeCellReader reader;
  late MemoryCellMissCache misses;
  late FirestoreCellSource source;

  setUp(() {
    reader = FakeCellReader();
    misses = MemoryCellMissCache();
    source = FirestoreCellSource(reader: reader, misses: misses);
  });

  final center = Geohash.encode(_lat, _lng, 5);

  group('FirestoreCellSource.load', () {
    test('normal file: unzips the households of a cell', () async {
      reader.seed(_north(3));
      final doc = await source.load(center);
      expect(doc, isNotNull);
      expect(doc!.isStub, isFalse);
      expect(doc.version, _release);
      expect(doc.records.map((r) => r.id), ['h0', 'h1', 'h2']);
      final r = doc.records.first;
      expect(r.address, 'H0 HELIX ST');
      expect(r.cityStateZip, 'SPRING VALLEY, CA 91977');
      expect(r.latitude, closeTo(_lat + 0.0001, 1e-9));
      expect(r.geohash, Geohash.encode(r.latitude, r.longitude, 9));
      expect(reader.serverReads, [center]);
    });

    test('split stub: returns the stub, children are separate docs', () async {
      reader.seed(_north(3), split: {center});
      final stub = await source.load(center);
      expect(stub!.isStub, isTrue);
      expect(stub.split, 6);
      expect(stub.records, isEmpty);
      final child = Geohash.encode(_lat + 0.0001, _lng, 6);
      final doc = await source.load(child);
      expect(doc!.records.map((r) => r.id), ['h0', 'h1', 'h2']);
    });

    test('missing cell (404): null, remembered for a day', () async {
      var now = DateTime(2026, 11, 14, 9);
      misses = MemoryCellMissCache(now: () => now);
      source = FirestoreCellSource(reader: reader, misses: misses);

      expect(await source.load(center), isNull);
      expect(reader.serverReads, [center]);

      // Same session: from memory.
      expect(await source.load(center), isNull);
      // App restarted (new source, same miss cache): still no read.
      source = FirestoreCellSource(reader: reader, misses: misses);
      expect(await source.load(center), isNull);
      expect(reader.serverReads, [center]);

      // A day later the cell may have been seeded: read again.
      reader.seed(_north(2));
      now = now.add(const Duration(days: 1, minutes: 1));
      source = FirestoreCellSource(reader: reader, misses: misses);
      expect((await source.load(center))!.records, hasLength(2));
      expect(reader.serverReads, [center, center]);
    });

    test('network error: thrown, not remembered as missing', () async {
      reader.seed(_north(2));
      reader.failNextServerRead = FirebaseException(
        plugin: 'cloud_firestore',
        code: 'unavailable',
      );
      await expectLater(source.load(center), throwsA(isA<FirebaseException>()));
      expect((await source.load(center))!.records, hasLength(2));
    });

    test('only prefixes of 5+ characters', () {
      expect(() => source.load('9muf'), throwsArgumentError);
    });

    test('a cell read before costs 0 reads after a restart', () async {
      reader.seed(_north(3));
      await source.load(center);
      final restarted = FirestoreCellSource(reader: reader, misses: misses);
      await restarted.load(center);
      expect(reader.serverReads, [center]);
      expect(restarted.stats.cacheHits, 1);
      expect(restarted.stats.serverReads, 0);
    });
  });

  group('CellArea', () {
    test('nearest 50 from the 3x3 cells, sorted by distance', () async {
      final homes = _north(120, step: 0.00005);
      reader.seed(homes);
      final area = source.area(latitude: _lat, longitude: _lng);
      await area.ensure(10);

      expect(area.isComplete, isTrue);
      expect(area.isUnavailable, isFalse);
      expect(area.records.map((r) => r.id), _nearestIds(homes, 50));
      final d = [for (final r in area.records) area.distanceOf(r.id)!];
      expect(d, orderedEquals([...d]..sort()));
      // 50+ found: the 5x5 ring is not read.
      expect(reader.serverReads.toSet(), blockCells(_lat, _lng, 1).toSet());
      expect(reader.serverReads, hasLength(9));
      expect(area.contains('h0'), isTrue);
      expect(area.contains('h119'), isFalse);
      expect(area.extentMeters, d.last);
    });

    test('fewer than 50 in 3x3: expands once to 5x5, no further', () async {
      // 10 homes near the center, 30 two cells away, 30 three cells away.
      final cell = Geohash.bounds(center);
      final h = cell.maxLat - cell.minLat;
      final midLat = (cell.minLat + cell.maxLat) / 2;
      final midLng = (cell.minLng + cell.maxLng) / 2;
      final homes = [
        ..._north(10),
        for (var i = 0; i < 30; i++)
          (id: 'ring$i', lat: midLat + 2 * h + i * 0.00001, lng: midLng),
        for (var i = 0; i < 30; i++)
          (id: 'far$i', lat: midLat + 3 * h + i * 0.00001, lng: midLng),
      ];
      reader.seed(homes);
      final area = source.area(latitude: _lat, longitude: _lng);
      await area.ensure(50);

      expect(area.records, hasLength(40));
      expect(area.records.where((r) => r.id.startsWith('far')), isEmpty);
      expect(area.records.take(10).map((r) => r.id), _nearestIds(homes, 10));
      expect(reader.serverReads, hasLength(25));
      expect(reader.serverReads.toSet(), blockCells(_lat, _lng, 2).toSet());
    });

    test('split cell: children read nearest-first, only as needed', () async {
      // 60 homes within ~70 m of the center, 200 more spread over the cell.
      final cell = Geohash.bounds(center);
      final homes = [
        ..._north(60, step: 0.00001),
        for (var i = 0; i < 200; i++)
          (
            id: 'spread$i',
            lat:
                cell.minLat +
                (cell.maxLat - cell.minLat) * ((i * 37) % 200) / 200,
            lng:
                cell.minLng +
                (cell.maxLng - cell.minLng) * ((i * 91) % 200) / 200,
          ),
      ];
      reader.seed(homes, split: {center});
      final area = source.area(latitude: _lat, longitude: _lng);
      await area.ensure(50);

      expect(area.records.map((r) => r.id), _nearestIds(homes, 50));
      final childReads = reader.serverReads.where((p) => p.length == 6);
      expect(childReads, isNotEmpty);
      expect(childReads.length, lessThan(32));
      // 9 p5 docs (the stub and 8 neighbours) + the children needed.
      expect(reader.serverReads.where((p) => p.length == 5), hasLength(9));
    });

    test('no cells anywhere: unavailable (not "0 households")', () async {
      final area = source.area(latitude: _lat, longitude: _lng);
      await area.ensure(50);
      expect(area.isComplete, isTrue);
      expect(area.isUnavailable, isTrue);
      expect(area.records, isEmpty);
      expect(reader.serverReads, hasLength(25));
    });

    test('opening the area again costs 0 reads', () async {
      reader.seed(_north(120, step: 0.00005));
      await source.area(latitude: _lat, longitude: _lng).ensure(50);
      final first = reader.serverReads.length;

      // Same session (memory).
      await source.area(latitude: _lat, longitude: _lng).ensure(50);
      // After a restart (device cache; missing neighbours remembered).
      final restarted = FirestoreCellSource(reader: reader, misses: misses);
      final again = restarted.area(latitude: _lat, longitude: _lng);
      await again.ensure(50);

      expect(reader.serverReads, hasLength(first));
      expect(again.records, hasLength(50));
    });

    test('a failed load can be retried', () async {
      reader.seed(_north(60));
      reader.failNextServerRead = FirebaseException(
        plugin: 'cloud_firestore',
        code: 'unavailable',
      );
      final area = source.area(latitude: _lat, longitude: _lng);
      await expectLater(area.ensure(50), throwsA(isA<FirebaseException>()));
      expect(area.isComplete, isFalse);
      await area.ensure(50);
      expect(area.records, hasLength(50));
    });
  });
}
