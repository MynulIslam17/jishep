import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gps_cielo/core/models/household_model.dart';
import 'package:gps_cielo/core/services/address_check_service.dart';
import 'package:gps_cielo/shared/widgets/household/address_check_tile.dart';

// The backend responses below are hand-written in the shape enrichHousehold
// returns; they are not from a live Melissa call.
HouseholdModel home({
  String address = '1240 NEW JERSEY AVE NW APT 4B',
  String cityStateZip = 'WASHINGTON, DC 20001',
}) => HouseholdModel(
  id: 'ovt:08b2a1',
  number: 1,
  address: address,
  cityStateZip: cityStateZip,
  latitude: 38.9,
  longitude: -77.0,
);

void main() {
  group('AddressCheckService.partsOf', () {
    test('splits "CITY, ST ZIP"', () {
      final p = AddressCheckService.partsOf(home())!;
      expect(p.line, '1240 NEW JERSEY AVE NW APT 4B');
      expect(p.city, 'WASHINGTON');
      expect(p.state, 'DC');
      expect(p.zip, '20001');
    });

    test('state only with a ZIP, or city without ZIP, are enough', () {
      expect(
        AddressCheckService.partsOf(home(cityStateZip: 'CA 92154'))?.zip,
        '92154',
      );
      expect(
        AddressCheckService.partsOf(home(cityStateZip: 'NEWARK, NJ'))?.city,
        'NEWARK',
      );
    });

    test('no house number, or only a state, cannot be checked', () {
      expect(AddressCheckService.partsOf(home(address: 'MAIN ST')), isNull);
      expect(AddressCheckService.partsOf(home(cityStateZip: 'CA')), isNull);
      expect(AddressCheckService.partsOf(home(cityStateZip: '')), isNull);
    });
  });

  group('AddressCheckService.check', () {
    test('sends only the household id and address parts', () async {
      late Map<String, Object?> sent;
      final service = AddressCheckService(
        call: (data) async {
          sent = data;
          return {
            'status': 'verified',
            'residential': true,
            'geocodeLevel': 'rooftop',
            'address': {
              'line': '1240 NEW JERSEY AVE NW',
              'suite': 'APT 4B',
              'city': 'Washington',
              'state': 'DC',
              'zip': '20001-1234',
            },
            'checkedAt': '2026-11-21T12:00:00.000Z',
            'cached': false,
          };
        },
      );
      final r = await service.check(home());
      expect(sent.keys.toSet(), {
        'householdId',
        'line',
        'city',
        'state',
        'zip',
        'includeProperty',
      });
      expect(r.summary, 'Verified residential address');
      expect(r.verifiedLine, '1240 NEW JERSEY AVE NW APT 4B');
      expect(r.verifiedCityStateZip, 'Washington, DC 20001-1234');
      expect(r.checkedAt, DateTime.utc(2026, 11, 21, 12));
    });

    test('business, unknown and no-match summaries never invent data', () {
      expect(
        AddressCheck.fromMap({
          'status': 'verified',
          'residential': false,
        }).summary,
        'Verified business address',
      );
      expect(
        AddressCheck.fromMap({'status': 'partial'}).summary,
        'Partly verified address (home or business unknown)',
      );
      final none = AddressCheck.fromMap({'status': 'not_found'});
      expect(none.summary, 'Melissa has no match for this address');
      expect(none.verifiedLine, isNull);
    });

    test('backend errors become plain messages', () async {
      Future<void> expectMessage(String code, String reason, String text) {
        final service = AddressCheckService(
          call: (_) async =>
              throw FirebaseFunctionsException(code: code, message: reason),
        );
        return expectLater(
          service.check(home()),
          throwsA(
            isA<AddressCheckException>().having(
              (e) => e.message,
              'message',
              contains(text),
            ),
          ),
        );
      }

      await expectMessage('resource-exhausted', 'out_of_credits', 'paused');
      await expectMessage('resource-exhausted', 'user_daily_limit', 'limit');
      await expectMessage('unavailable', 'unavailable', 'unavailable');
      await expectMessage('not-found', 'x', 'not set up');
    });

    test('no network: a plain message, nothing thrown raw', () {
      final service = AddressCheckService(
        call: (_) async => throw Exception('socket closed'),
      );
      expect(service.check(home()), throwsA(isA<AddressCheckException>()));
    });

    test('a home without a street address is not sent', () async {
      var calls = 0;
      final service = AddressCheckService(
        call: (_) async {
          calls++;
          return {};
        },
      );
      await expectLater(
        service.check(home(address: 'NO NUMBER')),
        throwsA(isA<AddressCheckException>()),
      );
      expect(calls, 0);
    });
  });

  group('AddressCheckTile', () {
    Future<void> pump(WidgetTester tester, Widget child) => tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (_, _) => MaterialApp(home: Scaffold(body: child)),
      ),
    );

    testWidgets('checks only on tap, then shows the result and source', (
      tester,
    ) async {
      var calls = 0;
      await pump(
        tester,
        AddressCheckTile(
          household: home(),
          service: AddressCheckService(
            call: (_) async {
              calls++;
              return {'status': 'verified', 'residential': true};
            },
          ),
        ),
      );
      expect(calls, 0);
      await tester.tap(find.byKey(const ValueKey('address-check-button')));
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(find.text('Verified residential address'), findsOneWidget);
      expect(
        find.textContaining('Address and property data by Melissa'),
        findsOneWidget,
      );
    });

    testWidgets('shows the error and keeps the button for a retry', (
      tester,
    ) async {
      await pump(
        tester,
        AddressCheckTile(
          household: home(),
          service: AddressCheckService(
            call: (_) async => throw FirebaseFunctionsException(
              code: 'resource-exhausted',
              message: 'out_of_credits',
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('address-check-button')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('address-check-error')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('address-check-button')),
        findsOneWidget,
      );
    });

    testWidgets('shows the recorded owner and reports it', (tester) async {
      String? reported;
      await pump(
        tester,
        AddressCheckTile(
          household: home(),
          onOwner: (name) => reported = name,
          service: AddressCheckService(
            call: (_) async => {
              'status': 'verified',
              'residential': true,
              'property': {
                'status': 'found',
                'useGroup': 'Single Family Residential',
                'owner': {'name': 'MARIA LOPEZ', 'isCompany': false},
              },
            },
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('address-check-button')));
      await tester.pumpAndSettle();
      expect(find.text('MARIA LOPEZ'), findsOneWidget);
      expect(find.textContaining('may not live here'), findsOneWidget);
      expect(reported, 'MARIA LOPEZ');
    });

    testWidgets('a parcel without an owner name says so', (tester) async {
      await pump(
        tester,
        AddressCheckTile(
          household: home(),
          service: AddressCheckService(
            call: (_) async => {
              'status': 'verified',
              'property': {'status': 'found', 'ownerRequested': true},
            },
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('address-check-button')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('address-check-no-owner')),
        findsOneWidget,
      );
    });

    testWidgets('owner names off: no "no owner" line', (tester) async {
      await pump(
        tester,
        AddressCheckTile(
          household: home(),
          service: AddressCheckService(
            call: (_) async => {
              'status': 'verified',
              'property': {'status': 'found', 'ownerRequested': false},
            },
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('address-check-button')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('address-check-no-owner')),
        findsNothing,
      );
    });

    testWidgets('hidden when there is no full street address', (tester) async {
      await pump(tester, AddressCheckTile(household: home(address: 'MAIN ST')));
      expect(find.byKey(const ValueKey('address-check')), findsNothing);
    });
  });

  test('property details become one line; none when not found', () {
    final r = AddressCheck.fromMap({
      'status': 'verified',
      'residential': true,
      'property': {
        'status': 'found',
        'useGroup': 'Single Family Residential',
        'yearBuilt': 1962,
      },
    });
    expect(r.propertyLine, 'Single Family Residential · built 1962');
    expect(
      AddressCheck.fromMap({
        'status': 'verified',
        'property': {'status': 'not_found'},
      }).propertyLine,
      isNull,
    );
    expect(AddressCheck.fromMap({'status': 'verified'}).propertyLine, isNull);
  });

  test('owner name is the title unless the user named the home', () {
    final h = home().copyWith(ownerName: 'MARIA LOPEZ');
    expect(h.displayName, 'MARIA LOPEZ');
    expect(h.showsOwnerName, isTrue);
    final named = h.withName('Maria');
    expect(named.displayName, 'Maria');
    expect(named.showsOwnerName, isFalse);
    expect(named.ownerName, 'MARIA LOPEZ');
    expect(home().displayName, 'Unknown Resident');
    // The owner is never written to the user's status document.
    expect(h.toStatusFirestore().containsKey('ownerName'), isFalse);
  });

  test('owner parsed from the response; company flag kept', () {
    final r = AddressCheck.fromMap({
      'status': 'verified',
      'property': {
        'status': 'found',
        'owner': {'name': 'ACME HOLDINGS LLC', 'isCompany': true},
      },
    });
    expect(r.ownerName, 'ACME HOLDINGS LLC');
    expect(r.ownerIsCompany, isTrue);
    expect(AddressCheck.fromMap({'status': 'verified'}).ownerName, isNull);
  });

  test('the fictional emulator fixture is recognised', () {
    expect(
      AddressCheck.fromMap({
        'status': 'verified',
        'codes': ['AS01', 'TEST'],
      }).isTestFixture,
      isTrue,
    );
    expect(
      AddressCheck.fromMap({
        'status': 'verified',
        'codes': ['AS01'],
      }).isTestFixture,
      isFalse,
    );
  });
}
