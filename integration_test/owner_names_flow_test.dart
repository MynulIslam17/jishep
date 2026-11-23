// End-to-end check of the household-name flow on a real device/simulator.
//
// LOCAL EMULATORS ONLY (never production): needs
//   --dart-define=FIREBASE_EMULATOR_HOST=10.0.2.2 (Android) / localhost (iOS)
//   --dart-define=MELISSA_OWNERS=true
//   --dart-define=TEST_EMAIL=... --dart-define=TEST_PASSWORD=...  (local test
//   account, from .local-backups/TEST_LOGIN.txt; never committed)
// Run with test_driver/integration_test.dart so screenshots are saved on the
// host (SCREENSHOT_DIR). No names are written in this file: it checks the
// names the app shows against the records the app loaded.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:gps_cielo/core/constants/firestore_paths.dart';
import 'package:gps_cielo/core/models/household_model.dart';
import 'package:gps_cielo/core/services/household_store.dart';
import 'package:gps_cielo/main.dart' as app;
import 'package:gps_cielo/shared/widgets/navigation/app_bottom_navigation_bar.dart';
import 'package:integration_test/integration_test.dart';

const _email = String.fromEnvironment('TEST_EMAIL');
const _password = String.fromEnvironment('TEST_PASSWORD');
const _emulator = String.fromEnvironment('FIREBASE_EMULATOR_HOST');

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('owner names: Home, Neighborhood, Prayer List, round, history', (
    tester,
  ) async {
    expect(_emulator, isNotEmpty, reason: 'local emulators only');
    expect(_email, isNotEmpty);

    Future<void> until(
      bool Function() done, {
      Duration timeout = const Duration(seconds: 90),
      String what = 'condition',
      String Function()? detail,
    }) async {
      final end = DateTime.now().add(timeout);
      while (!done()) {
        if (DateTime.now().isAfter(end)) {
          fail('timed out waiting for $what ${detail?.call() ?? ''}');
        }
        await tester.pump(const Duration(milliseconds: 250));
      }
    }

    var surface = false;
    Future<void> shot(String name) async {
      if (defaultTargetPlatform == TargetPlatform.android && !surface) {
        await binding.convertFlutterSurfaceToImage();
        surface = true;
      }
      await tester.pump(const Duration(milliseconds: 500));
      await binding.takeScreenshot(name);
    }

    Future<void> tab(String label) async {
      await tester.tap(
        find.descendant(
          of: find.byType(AppBottomNavigationBar),
          matching: find.text(label),
        ),
      );
      await tester.pump(const Duration(seconds: 1));
    }

    await app.bootstrap();
    final auth = FirebaseAuth.instance;
    if (auth.currentUser?.email != _email) {
      await auth.signOut();
      await auth.signInWithEmailAndPassword(email: _email, password: _password);
    }
    final uid = auth.currentUser!.uid;
    await tester.pumpWidget(const app.GpsCieloApp());

    // ---- Home: 50 homes, each titled with its recorded owner -------------
    await until(
      () =>
          Get.isRegistered<HouseholdStore>() &&
          Get.find<HouseholdStore>().homeHouseholds.length >= 50,
      what: '50 homes on Home',
    );
    final store = Get.find<HouseholdStore>();
    // Owner records load alongside the homes; wait for them (counts only
    // in the message, never names).
    String counts() {
      final h = store.homeHouseholds;
      return 'homes=${h.length} named=${h.where((x) => x.ownerName != null).length}';
    }

    await until(
      () => store.homeHouseholds.where((h) => h.ownerName != null).length >= 25,
      what: 'owner names on the 50 homes',
      detail: counts,
    );
    final homes = store.homeHouseholds.toList();
    expect(homes.length, 50);
    expect(homes.map((h) => h.id).toSet().length, 50);
    for (final h in homes.where((h) => h.residentName == null)) {
      // Owner is the title when recorded; otherwise "Unknown Resident".
      expect(h.displayName, h.ownerName ?? HouseholdModel.unnamed);
    }
    // ignore: avoid_print
    print('named homes: ${counts()}');
    await until(
      () => find.text('View all 50').evaluate().isNotEmpty,
      what: 'View all 50',
    );
    // Home's "Pray for today" cards: owner title + street address under it.
    bool shown(h) =>
        h.ownerName != null && find.text(h.displayName).evaluate().isNotEmpty;
    await until(() => homes.any(shown), what: 'a card titled with an owner');
    final card = homes.firstWhere(shown);
    expect(find.text(card.address), findsWidgets);
    for (final noise in [
      'Public Record',
      'Melissa',
      'may not live',
      'verified resident',
    ]) {
      expect(find.textContaining(noise), findsNothing, reason: noise);
    }
    await shot('1_home');

    // ---- Neighborhood -----------------------------------------------------
    await tab('Neighborhood');
    await until(
      () => find.byKey(const ValueKey('area-count')).evaluate().isNotEmpty,
      what: 'neighborhood list',
    );
    expect(
      (tester.widget<Text>(find.byKey(const ValueKey('area-count'))).data ??
          ''),
      startsWith('50 households'),
    );
    // The neighborhood list uses the normal home ids (what live users have):
    // owner names are added to them by address.
    final area = store.areaHouseholds;
    final areaNamed = area.where((h) => h.ownerName != null).length;
    // ignore: avoid_print
    print(
      'neighborhood: homes=${area.length} named=$areaNamed '
      'normalIds=${area.where((h) => !h.id.startsWith('mel:')).length}',
    );
    expect(area.every((h) => !h.id.startsWith('mel:')), isTrue);
    expect(areaNamed, greaterThanOrEqualTo(25));
    await shot('2_neighborhood');

    // ---- Prayer List: pray for one home, check round + history, undo ------
    await tab('Prayer List');
    await tester.pump(const Duration(seconds: 2));
    final target = homes.firstWhere(
      (h) =>
          !h.isPrayed &&
          find
              .byKey(ValueKey('pray-chip-${h.id}'))
              .hitTestable()
              .evaluate()
              .isNotEmpty,
      orElse: () => fail('no unprayed home visible on the Prayer List'),
    );
    expect(find.text(target.displayName), findsWidgets);
    await shot('3_prayer_list');
    final prayedBefore = store.prayedCount.value;
    final offeredBefore = store.prayersOffered.value;
    await tester.tap(find.byKey(ValueKey('pray-chip-${target.id}')));
    await until(
      () => store.findById(target.id)?.isPrayed == true,
      what: 'prayed',
    );
    expect(store.prayedCount.value, prayedBefore + 1);
    await until(
      () => store.prayersOffered.value == offeredBefore + 1,
      what: 'lifetime prayers +1',
    );

    final db = FirebaseFirestore.instance;
    final log = await db
        .collection(FirestorePaths.userPrayerLog(uid))
        .where('householdId', isEqualTo: target.id)
        .get();
    expect(log.docs, isNotEmpty, reason: 'prayer history event written');
    final rounds = await db
        .collection(FirestorePaths.userPrayerRounds(uid))
        .get();
    final round = rounds.docs.where(
      (d) => (d.data()['members'] as List?)?.length == 50,
    );
    expect(round, isNotEmpty, reason: 'the round keeps the same 50 homes');
    expect(
      Set.of(List<String>.from(round.first.data()['householdIds'] as List)),
      homes.map((h) => h.id).toSet(),
    );
    await shot('4_prayed');

    // ---- Household details: owner title, second owner when recorded -------
    final withSecond = homes.where(
      (h) => h.ownerSecondName != null && h.residentName == null,
    );
    expect(withSecond, isNotEmpty, reason: 'some records have a second owner');

    // ---- Profile: lifetime prayer count ------------------------------------
    await tab('Profile');
    await until(
      () => find.text('Prayers').evaluate().isNotEmpty,
      what: 'profile impact',
    );
    expect(find.text('${store.prayersOffered.value}'), findsWidgets);
    await shot('5_profile');

    // Undo the test prayer (leave the account as it was).
    await store.togglePray(target.id);
    await until(
      () => store.findById(target.id)?.isPrayed == false,
      what: 'undo',
    );
    expect(store.prayedCount.value, prayedBefore);
  });
}
