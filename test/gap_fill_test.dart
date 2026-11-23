import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gps_cielo/core/data/cell_source.dart';
import 'package:gps_cielo/core/data/gap_fill.dart';
import 'package:gps_cielo/core/data/geo_record.dart';

import 'support/fake_cell_reader.dart';

// Melissa records here are hand-written in the shape discoverNearby
// returns (that shape is tested against a REAL Reverse GeoCoder response in
// functions/test/discover.test.js).
const lat = 36.1699;
const lng = -115.1398;

Map<String, Object?> mel(int i, {double dLat = 0, String? line}) => {
  'id': 'mel:$i',
  'line': line ?? '${500 + i} FREMONT ST',
  'city': 'Las Vegas',
  'state': 'NV',
  'zip': '89101',
  'latitude': lat + dLat + i * 0.0002,
  'longitude': lng,
};

CellArea overture(FakeCellReader reader) => FirestoreCellSource(
  reader: reader,
  misses: MemoryCellMissCache(),
).area(latitude: lat, longitude: lng);

GapFilledArea area(
  FakeCellReader reader,
  Future<Map<Object?, Object?>> Function(Map<String, Object?>) call,
) => GapFilledArea(
  inner: overture(reader),
  service: GapFillService(call: call),
  latitude: lat,
  longitude: lng,
);

void main() {
  test('Overture has 50: Melissa is never called', () async {
    final reader = FakeCellReader()
      ..seed([
        for (var i = 0; i < 60; i++)
          (id: 'ovt$i', lat: lat + i * 0.0001, lng: lng),
      ]);
    var calls = 0;
    final a = area(reader, (_) async {
      calls++;
      return {};
    });
    await a.ensure(50);
    expect(calls, 0);
    expect(a.records.length, 50);
    expect(a.gapStatus, GapFillStatus.notNeeded);
  });

  test(
    'sparse Overture: tops up to 50, Overture kept, nearest first',
    () async {
      final reader = FakeCellReader()
        ..seed([
          for (var i = 0; i < 12; i++)
            (id: 'ovt$i', lat: lat + i * 0.0003, lng: lng),
        ]);
      late Map<String, Object?> sent;
      final a = area(reader, (data) async {
        sent = data;
        return {
          'records': [for (var i = 0; i < 38; i++) mel(i)],
        };
      });
      await a.ensure(50);
      expect(sent['have'], 12);
      expect(a.records.length, 50);
      expect(a.melissaCount, 38);
      expect(a.records.where((r) => r.id.startsWith('ovt')).length, 12);
      expect(a.gapStatus, GapFillStatus.added);
      final d = [for (final r in a.records) a.distanceOf(r.id)!];
      expect(d, [...d]..sort());
    },
  );

  test(
    'no Overture data at all (e.g. Hawaii): Melissa alone, real count',
    () async {
      final a = area(
        FakeCellReader(),
        (_) async => {
          'records': [for (var i = 0; i < 7; i++) mel(i)],
        },
      );
      await a.ensure(50);
      expect(a.records.length, 7);
      expect(a.isUnavailable, isFalse);
    },
  );

  test('nothing anywhere: still "not available", never invented', () async {
    final a = area(FakeCellReader(), (_) async => {'records': []});
    await a.ensure(50);
    expect(a.records, isEmpty);
    expect(a.isUnavailable, isTrue);
    expect(a.gapStatus, GapFillStatus.noneFound);
  });

  test('gap-filler errors keep the Overture homes and explain why', () async {
    final reader = FakeCellReader()..seed([(id: 'ovt0', lat: lat, lng: lng)]);
    final a = area(
      reader,
      (_) async => throw FirebaseFunctionsException(
        code: 'resource-exhausted',
        message: 'out_of_credits',
      ),
    );
    await a.ensure(50);
    expect(a.records.single.id, 'ovt0');
    expect(a.gapStatus, GapFillStatus.failed);
    expect(a.gapMessage, contains('paused'));

    final offline = area(
      FakeCellReader()..seed([(id: 'ovt0', lat: lat, lng: lng)]),
      (_) async => throw Exception('no network'),
    );
    await offline.ensure(50);
    expect(offline.records.length, 1);
    expect(offline.gapStatus, GapFillStatus.failed);
  });

  test('a disabled server is reported plainly', () {
    expect(
      GapFillService.messageFor('gap_filler_disabled'),
      contains('not turned on'),
    );
    expect(GapFillService.messageFor('user_daily_limit'), contains('today'));
  });

  group('merge', () {
    GeoRecord o(String id, String address, double dLat) => GeoRecord(
      id: id,
      latitude: lat + dLat,
      longitude: lng,
      geohash: '',
      address: address,
    );

    test('same address or same number within 30 m is a duplicate', () {
      final merged = GapFilledArea.merge(
        [o('ovt1', '510 FREMONT ST', 0.001)],
        [
          GapFillService.recordFrom(mel(1, line: '510 Fremont St'))!,
          GapFillService.recordFrom({
            ...mel(2, line: '510 FREMONT STREET'),
            'latitude': lat + 0.001 + 0.0001,
          })!,
          GapFillService.recordFrom(mel(3, line: '999 OTHER AVE'))!,
        ],
        lat,
        lng,
      );
      expect(merged.map((r) => r.id), containsAll(['ovt1', 'mel:3']));
      expect(merged.length, 2);
    });

    test('apartments are separate homes', () {
      final merged = GapFilledArea.merge(
        [o('ovt1', '510 FREMONT ST APT 1', 0.001)],
        [GapFillService.recordFrom(mel(1, line: '510 FREMONT ST APT 2'))!],
        lat,
        lng,
      );
      expect(merged.length, 2);
    });

    test('never more than 50', () {
      final merged = GapFilledArea.merge(
        [for (var i = 0; i < 30; i++) o('ovt$i', '${i + 1} A ST', i * 0.0001)],
        [
          for (var i = 0; i < 40; i++)
            GapFillService.recordFrom(mel(i, line: '${i + 1} B ST'))!,
        ],
        lat,
        lng,
      );
      expect(merged.length, 50);
    });
  });

  test('recordFrom rejects bad records and formats the city line', () {
    final r = GapFillService.recordFrom(mel(1))!;
    expect(r.cityStateZip, 'LAS VEGAS, NV 89101');
    expect(r.geohash.length, 9);
    expect(GapFillService.recordFrom({'id': 'x:1', 'line': '1 A'}), isNull);
    expect(GapFillService.recordFrom({...mel(1), 'latitude': 'nope'}), isNull);
  });
}
