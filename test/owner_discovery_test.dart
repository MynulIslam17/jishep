import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gps_cielo/core/data/cell_source.dart';
import 'package:gps_cielo/core/data/geo_record.dart';
import 'package:gps_cielo/core/data/owner_discovery.dart';
import 'package:gps_cielo/core/models/household_model.dart';
import 'package:gps_cielo/shared/widgets/household/household_row.dart';

import 'support/fake_cell_reader.dart';

// Records here are hand-written in the shape `discoverOwners` returns (that
// function is tested with Melissa-format responses and REAL saved Melissa
// responses in functions/test/owners.test.js). Names say TEST on purpose.
const lat = 32.6401;
const lng = -117.0842;

Map<String, Object?> owned(int i, {String? owner = 'OWNER TEST'}) => {
  'id': 'mel:${5000 + i}',
  'line': '${100 + i} Test St',
  'city': 'Chula Vista',
  'state': 'CA',
  'zip': '91910',
  'latitude': lat + i * 0.0002,
  'longitude': lng,
  'distanceMeters': 20 * i,
  if (owner != null)
    'owner': {'name': '$owner $i', 'isCompany': false, 'isTrust': false},
  'classification': {
    'kind': 'single_family',
    'label': 'Single Family Residential',
  },
};

CellArea overture(FakeCellReader reader) => FirestoreCellSource(
  reader: reader,
  misses: MemoryCellMissCache(),
).area(latitude: lat, longitude: lng);

OwnerArea area(
  FakeCellReader reader,
  Future<Map<Object?, Object?>> Function(Map<String, Object?>) call,
) => OwnerArea(
  service: OwnerDiscoveryService(call: call),
  latitude: lat,
  longitude: lng,
);

FakeCellReader seeded() => FakeCellReader()
  ..seed([
    for (var i = 0; i < 60; i++) (id: 'ovt$i', lat: lat + i * 0.0001, lng: lng),
  ]);

void main() {
  test('Melissa-first: only named homes, as many as really found', () async {
    late Map<String, Object?> sent;
    final a = area(seeded(), (data) async {
      sent = data;
      return {
        'records': [for (var i = 1; i <= 23; i++) owned(i)],
        'coverage': 'partial',
        'stats': {'addressesFound': 100, 'lookups': 80, 'named': 23},
      };
    });
    await a.ensure(50);
    expect(sent, {'latitude': lat, 'longitude': lng, 'target': 50});
    expect(a.unavailableReason, isNull);
    expect(a.isComplete, isTrue);
    expect(a.records.length, 23); // no placeholders up to 50
    expect(a.records.every((r) => r.ownerName != null), isTrue);
    expect(a.records.any((r) => r.id.startsWith('ovt')), isFalse);
    expect(a.result!.full, isFalse);
    expect(a.result!.stats['lookups'], 80);
    expect(a.contains('mel:5001'), isTrue);
    expect(a.extentMeters, greaterThan(0));
  });

  test('records without an owner name are never shown', () async {
    final a = area(
      seeded(),
      (_) async => {
        'records': [
          owned(1),
          owned(2, owner: null),
          {
            ...owned(3),
            'owner': {'name': '  '},
          },
        ],
      },
    );
    await a.ensure(50);
    expect(a.records.map((r) => r.id), ['mel:5001']);
  });

  test('Melissa unavailable: empty, with the reason, never Overture', () async {
    final a = area(
      seeded(),
      (_) async => throw FirebaseFunctionsException(
        code: 'failed-precondition',
        message: 'owner_names_disabled',
      ),
    );
    await a.ensure(50);
    expect(
      a.unavailableReason,
      'Property owner lookups are not turned on yet.',
    );
    expect(a.records, isEmpty);
    expect(a.isUnavailable, isTrue);
    expect(a.sourceNote, a.unavailableReason);
  });

  test('another request is looking it up: wait and read its result', () async {
    var calls = 0;
    final a = OwnerArea(
      service: OwnerDiscoveryService(
        call: (_) async => ++calls == 1
            ? {
                'records': <Object>[],
                'pending': true,
                'completeness': 'unknown',
              }
            : {
                'records': [for (var i = 1; i <= 50; i++) owned(i)],
                'coverage': 'full',
                'completeness': 'complete',
              },
      ),
      latitude: lat,
      longitude: lng,
      retryDelay: Duration.zero,
    );
    await a.ensure(50);
    expect(calls, 2);
    expect(a.unavailableReason, isNull);
    expect(a.records.length, 50);
    expect(a.sourceNote, isNull); // normal result: no source text
  });

  test(
    'nothing stored for the area (cache only): empty state with why, no addresses',
    () async {
      final a = area(
        seeded(),
        (_) async => {
          'records': <Object>[],
          'completeness': 'unknown',
          'cached': true,
        },
      );
      await a.ensure(50);
      expect(a.unavailableReason, contains('not available for this area yet'));
      expect(a.records, isEmpty);
      expect(a.isUnavailable, isTrue);
      expect(a.isComplete, isTrue);
    },
  );

  test('fewer than 50 stored: the real count, never padded', () async {
    final a = area(
      seeded(),
      (_) async => {
        'records': [for (var i = 1; i <= 12; i++) owned(i)],
        'completeness': 'partial',
      },
    );
    await a.ensure(50);
    expect(a.records.length, 12);
    expect(a.records.every((r) => r.id.startsWith('mel:')), isTrue);
    expect(a.sourceNote, isNull); // the count itself is shown, not padded
    expect(a.isUnavailable, isFalse);
  });

  test('an area resolved with no owned homes says so (empty)', () async {
    final a = area(
      seeded(),
      (_) async => {'records': <Object>[], 'completeness': 'empty'},
    );
    await a.ensure(50);
    expect(a.records, isEmpty);
    expect(a.isUnavailable, isTrue);
    expect(a.sourceNote, contains('No homes with a recorded property owner'));
  });

  group('only a settled answer may fix a prayer round', () {
    test('stored homes, or a deliberate fallback: settled', () async {
      final named = area(
        seeded(),
        (_) async => {
          'records': [for (var i = 1; i <= 50; i++) owned(i)],
          'completeness': 'complete',
        },
      );
      expect(named.isSettled, isFalse); // not loaded yet
      await named.ensure(50);
      expect(named.isSettled, isTrue);

      final nothingStored = area(
        seeded(),
        (_) async => {'records': <Object>[], 'completeness': 'unknown'},
      );
      await nothingStored.ensure(50);
      expect(nothingStored.isSettled, isTrue);

      final off = area(
        seeded(),
        (_) async => throw FirebaseFunctionsException(
          code: 'failed-precondition',
          message: 'owner_names_disabled',
        ),
      );
      await off.ensure(50);
      expect(off.isSettled, isTrue);
    });

    test('still being looked up, or a passing error: not settled', () async {
      final pending = OwnerArea(
        service: OwnerDiscoveryService(
          call: (_) async => {
            'records': [owned(1)],
            'pending': true,
            'completeness': 'partial',
          },
        ),
        latitude: lat,
        longitude: lng,
        retryDelay: Duration.zero,
      );
      await pending.ensure(50);
      expect(pending.isSettled, isFalse);

      final network = area(seeded(), (_) async => throw Exception('offline'));
      await network.ensure(50);
      expect(network.records, isEmpty);
      expect(network.unavailableReason, isNotNull);
      expect(network.isSettled, isFalse);

      final server = area(
        seeded(),
        (_) async => throw FirebaseFunctionsException(
          code: 'unavailable',
          message: 'socket closed',
        ),
      );
      await server.ensure(50);
      expect(server.isSettled, isFalse);
    });
  });

  test('stored homes that may not be the nearest are labelled so', () async {
    final a = area(
      seeded(),
      (_) async => {
        'records': [for (var i = 1; i <= 50; i++) owned(i)],
        'coverage': 'full',
        'completeness': 'partial',
      },
    );
    await a.ensure(50);
    expect(a.sourceNote, isNull);
  });

  test('the second recorded owner is kept for the details sheet', () {
    final r = OwnerDiscoveryService.recordFrom({
      ...owned(2),
      'owner': {'name': 'OWNER TEST 2', 'secondName': 'SECOND OWNER TEST'},
    })!;
    expect(r.ownerSecondName, 'SECOND OWNER TEST');
    final h = HouseholdModel.fromRecord(record: r, number: 1);
    expect(h.ownerSecondName, 'SECOND OWNER TEST');
    expect(h.withName('Maria').ownerSecondName, 'SECOND OWNER TEST');
  });

  test('recordFrom keeps owner, entity flag and property class', () {
    final r = OwnerDiscoveryService.recordFrom({
      ...owned(1),
      'owner': {'name': 'TEST HOLDINGS LLC', 'isCompany': true},
      'classification': {'label': 'Townhouse'},
    })!;
    expect(r.ownerName, 'TEST HOLDINGS LLC');
    expect(r.ownerIsEntity, isTrue);
    expect(r.propertyClass, 'Townhouse');
    expect(r.address, '101 TEST ST');
    expect(r.cityStateZip, 'CHULA VISTA, CA 91910');
    expect(OwnerDiscoveryService.recordFrom({...owned(1), 'id': 'x'}), isNull);
  });

  test('a household from Melissa shows the owner and the property class', () {
    final h = HouseholdModel.fromRecord(
      record: OwnerDiscoveryService.recordFrom(owned(4))!,
      number: 1,
    );
    expect(h.displayName, 'OWNER TEST 4');
    expect(h.showsOwnerName, isTrue);
    expect(h.propertyClass, 'Single Family Residential');
    // A name the user typed still wins.
    expect(h.withName('Maria').displayName, 'Maria');
    expect(h.withName('Maria').propertyClass, 'Single Family Residential');
  });

  testWidgets(
    'card: owner name as the title, street address under it, nothing else',
    (tester) async {
      final h = HouseholdModel.fromRecord(
        record: const GeoRecord(
          id: 'mel:1',
          latitude: lat,
          longitude: lng,
          geohash: '',
          address: '101 TEST ST',
          cityStateZip: 'CHULA VISTA, CA 91910',
          ownerName: 'OWNER TEST 1',
          propertyClass: 'Single Family Residential',
        ),
        number: 1,
      );
      await tester.pumpWidget(
        ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (_, _) => MaterialApp(
            home: Scaffold(
              body: HouseholdRow(
                household: h,
                from: (latitude: lat, longitude: lng + 0.001),
              ),
            ),
          ),
        ),
      );
      expect(find.text('OWNER TEST 1'), findsOneWidget);
      // No labels, source or classification on the card.
      expect(find.textContaining('Public Record'), findsNothing);
      expect(find.textContaining('Melissa'), findsNothing);
      expect(find.textContaining('Single Family'), findsNothing);
      expect(find.textContaining('verified', findRichText: true), findsNothing);
      expect(find.text('101 TEST ST'), findsOneWidget);
      expect(find.textContaining('CHULA VISTA, CA 91910 · '), findsOneWidget);
      expect(find.text('Neighbor'), findsNothing);
      expect(find.textContaining('resident', findRichText: true), findsNothing);
    },
  );
}
