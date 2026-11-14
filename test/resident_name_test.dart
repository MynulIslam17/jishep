import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:gps_cielo/core/config/feature_flags.dart';
import 'package:gps_cielo/core/constants/firestore_paths.dart';
import 'package:gps_cielo/core/data/cell_source.dart';
import 'package:gps_cielo/core/data/household_repository.dart';
import 'package:gps_cielo/core/models/household_model.dart';
import 'package:gps_cielo/core/models/user_model.dart';
import 'package:gps_cielo/core/services/household_store.dart';
import 'package:gps_cielo/shared/widgets/bottom_sheets/household_detail_bottom_sheet.dart';

import 'support/fake_cell_reader.dart';
import 'support/fake_household_repository.dart';

HouseholdModel _home({String? name}) => HouseholdModel(
  id: 'h1',
  number: 1,
  residentName: name,
  address: '3510 HELIX ST',
  cityStateZip: 'SPRING VALLEY, CA 91977',
);

void main() {
  group('HouseholdModel name', () {
    test('placeholders and blanks are no name', () {
      for (final raw in [
        null,
        '',
        '   ',
        'Resident',
        'resident',
        'Neighbor',
        'Demo Household 007',
      ]) {
        expect(HouseholdModel.cleanName(raw), isNull, reason: '$raw');
      }
      expect(HouseholdModel.cleanName('  Suzanne '), 'Suzanne');
      expect(HouseholdModel.cleanName('Demo Household family'), isNotNull);
    });

    test('names are cut to 120 characters', () {
      final name = HouseholdModel.cleanName('x' * 200)!;
      expect(name.length, HouseholdModel.maxNameLength);
    });

    test('title is the name, or "Neighbor"', () {
      expect(_home().displayName, 'Neighbor');
      expect(
        _home(name: 'Martha and Odalis Cordova').displayName,
        'Martha and Odalis Cordova',
      );
      expect(_home(name: 'Suzanne').withName(null).displayName, 'Neighbor');
      expect(_home().withName('Suzanne').residentName, 'Suzanne');
    });

    test('old placeholder names in status docs read as no name', () {
      for (final stored in ['Resident', 'Demo Household 012']) {
        final h = HouseholdModel.fromStatus(
          id: 'h1',
          status: {'residentName': stored},
          number: 1,
        );
        expect(h.residentName, isNull);
        expect(h.displayName, 'Neighbor');
      }
    });

    test('the status write never includes the name by itself', () {
      expect(
        _home(name: 'Suzanne').toStatusFirestore().containsKey('residentName'),
        isFalse,
      );
    });
  });

  group('HouseholdRepository.saveStatus', () {
    late FakeFirebaseFirestore db;
    late HouseholdRepository repo;
    DocumentReference<Map<String, dynamic>> doc() =>
        db.collection(FirestorePaths.userHouseholdStatus('alice')).doc('h1');

    setUp(() {
      db = FakeFirebaseFirestore();
      repo = HouseholdRepository(firestore: db);
    });

    test(
      'writes the name only when it changed; merge keeps the rest',
      () async {
        await doc().set({'notes': 'Met on Sunday', 'isPrayed': true});

        await repo.saveStatus(
          uid: 'alice',
          household: _home(
            name: 'Suzanne',
          ).copyWith(isPrayed: true, notes: 'Met on Sunday'),
          wasPrayed: true,
          nameChanged: true,
        );
        expect((await doc().get()).data()!['residentName'], 'Suzanne');
        expect((await doc().get()).data()!['notes'], 'Met on Sunday');

        // A status change without a name change leaves the name alone.
        await repo.saveStatus(
          uid: 'alice',
          household: _home().copyWith(isVisited: true, notes: 'Met on Sunday'),
          wasPrayed: true,
        );
        final data = (await doc().get()).data()!;
        expect(data['residentName'], 'Suzanne');
        expect(data['isVisited'], isTrue);
      },
    );

    test('removing the name deletes the field', () async {
      await doc().set({'residentName': 'Suzanne', 'isPrayed': false});
      await repo.saveStatus(
        uid: 'alice',
        household: _home(),
        wasPrayed: false,
        nameChanged: true,
      );
      expect((await doc().get()).data()!.containsKey('residentName'), isFalse);
    });
  });

  group('HouseholdStore names', () {
    late FakeHouseholdRepository repository;
    late FakeCellReader reader;
    late HouseholdStore store;

    UserModel user(String id) => UserModel(
      id: id,
      fullName: 'Test',
      email: '$id@example.com',
      address: 'Spring Valley, CA',
      latitude: 32.7448,
      longitude: -116.9989,
      radiusHomes: 10,
      searchRadiusKm: 5,
    );

    setUp(() {
      Get.testMode = true;
      FeatureFlags.useCellHouseholds = true;
      reader = FakeCellReader()
        ..seed([
          for (var i = 0; i < 20; i++)
            (id: 'h$i', lat: 32.7448 + 0.0002 * (i + 1), lng: -116.9989),
        ]);
      repository = FakeHouseholdRepository()
        ..cells = FirestoreCellSource(
          reader: reader,
          misses: MemoryCellMissCache(),
        );
      store = HouseholdStore(repository, FakeNotificationRepository());
    });

    tearDown(() => FeatureFlags.useCellHouseholds = false);

    HouseholdModel byId(List<HouseholdModel> list, String id) =>
        list.firstWhere((h) => h.id == id);

    test('unnamed households show "Neighbor" + the address', () async {
      await store.bindUser(user('alice'));
      final h = store.households.first;
      expect(h.displayName, 'Neighbor');
      expect(h.address, 'H0 HELIX ST');
    });

    test('adding a name shows it in every list, then removing it', () async {
      await store.bindUser(user('alice'));
      final h3 = byId(store.households, 'h3');

      await store.saveHousehold(h3.withName('Suzanne'));
      expect(repository.savedNames, [(id: 'h3', name: 'Suzanne')]);
      expect(byId(store.households, 'h3').displayName, 'Suzanne');
      expect(byId(store.areaHouseholds, 'h3').displayName, 'Suzanne');
      expect(byId(store.homeHouseholds, 'h3').displayName, 'Suzanne');
      expect(store.findById('h3')!.residentName, 'Suzanne');

      // Saving the same name again writes nothing.
      await store.saveHousehold(
        byId(store.households, 'h3').withName('Suzanne'),
      );
      expect(repository.savedNames, hasLength(1));

      await store.saveHousehold(byId(store.households, 'h3').withName(null));
      expect(repository.savedNames.last, (id: 'h3', name: null));
      expect(byId(store.households, 'h3').displayName, 'Neighbor');
    });

    test('a pray/follow-up change does not write the name', () async {
      await store.bindUser(user('alice'));
      await store.saveHousehold(byId(store.households, 'h1').withName('Ann'));
      await store.togglePray('h1');
      await store.toggleFollowUp('h1');
      expect(repository.savedNames, [(id: 'h1', name: 'Ann')]);
      expect(byId(store.households, 'h1').isPrayed, isTrue);
      expect(byId(store.households, 'h1').displayName, 'Ann');
    });

    test('a name from my other device appears', () async {
      await store.bindUser(user('alice'));
      repository.emitStatuses('alice', {
        'h2': {'residentName': 'The Cordovas', 'isPrayed': false},
      });
      await Future<void>.delayed(Duration.zero);
      expect(byId(store.households, 'h2').displayName, 'The Cordovas');
    });

    test("another user doesn't see my names", () async {
      repository.serverStatuses['alice'] = {
        'h4': {'residentName': 'Suzanne'},
      };
      await store.bindUser(user('bob'));
      expect(byId(store.households, 'h4').displayName, 'Neighbor');
      expect(repository.statusReads, isNotEmpty);
    });

    test('a failed write puts the old name back', () async {
      await store.bindUser(user('alice'));
      repository.failWith = FirebaseException(
        plugin: 'cloud_firestore',
        code: 'permission-denied',
      );
      await store.saveHousehold(byId(store.households, 'h5').withName('Ann'));
      expect(byId(store.households, 'h5').displayName, 'Neighbor');
    });
  });

  group('Household sheet: Add / Edit name', () {
    Widget app(HouseholdModel h, ValueChanged<HouseholdModel> onUpdated) =>
        ScreenUtilInit(
          designSize: const Size(393, 852),
          builder: (context, _) => MaterialApp(
            home: Scaffold(
              body: HouseholdDetailBottomSheet(
                household: h,
                onUpdated: onUpdated,
              ),
            ),
          ),
        );

    testWidgets('unnamed: "Neighbor", Add name → Save', (tester) async {
      HouseholdModel? saved;
      await tester.pumpWidget(app(_home(), (h) => saved = h));
      await tester.pumpAndSettle();
      expect(find.text('Neighbor'), findsWidgets);
      expect(find.text('3510 HELIX ST'), findsOneWidget);

      await tester.tap(find.text('Add name'));
      await tester.pumpAndSettle();
      expect(find.text('Remove name'), findsNothing);
      await tester.enterText(
        find.byKey(const ValueKey('resident-name-field')),
        '  Martha and Odalis Cordova ',
      );
      await tester.tap(find.byKey(const ValueKey('resident-name-save')));
      await tester.pumpAndSettle();

      expect(saved!.residentName, 'Martha and Odalis Cordova');
      expect(find.text('Martha and Odalis Cordova'), findsWidgets);
      expect(find.text('Edit name'), findsOneWidget);
    });

    testWidgets('named: Edit name → Remove name', (tester) async {
      HouseholdModel? saved;
      await tester.pumpWidget(app(_home(name: 'Suzanne'), (h) => saved = h));
      await tester.pumpAndSettle();
      expect(find.text('Suzanne'), findsWidgets);

      await tester.tap(find.text('Edit name'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('resident-name-remove')));
      await tester.pumpAndSettle();

      expect(saved, isNotNull);
      expect(saved!.residentName, isNull);
      expect(find.text('Neighbor'), findsWidgets);
    });

    testWidgets('saving an empty name removes it', (tester) async {
      HouseholdModel? saved;
      await tester.pumpWidget(app(_home(name: 'Suzanne'), (h) => saved = h));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit name'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('resident-name-field')),
        '   ',
      );
      await tester.tap(find.byKey(const ValueKey('resident-name-save')));
      await tester.pumpAndSettle();
      expect(saved!.residentName, isNull);
    });

    testWidgets('cancel changes nothing', (tester) async {
      HouseholdModel? saved;
      await tester.pumpWidget(app(_home(), (h) => saved = h));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add name'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('resident-name-field')),
        'Ann',
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(saved, isNull);
      expect(find.text('Add name'), findsOneWidget);
    });

    testWidgets('the field stops at 120 characters', (tester) async {
      await tester.pumpWidget(app(_home(), (_) {}));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add name'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('resident-name-field')),
        'x' * 150,
      );
      final field = tester.widget<TextField>(
        find.byKey(const ValueKey('resident-name-field')),
      );
      expect(field.controller!.text.length, 120);
    });
  });
}
