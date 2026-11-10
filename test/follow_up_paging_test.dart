import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:gps_cielo/core/data/household_repository.dart';
import 'package:gps_cielo/core/models/user_model.dart';
import 'package:gps_cielo/core/services/household_store.dart';
import 'package:gps_cielo/features/follow_up/domain/services/follow_up_service.dart';
import 'package:gps_cielo/features/follow_up/presentation/controllers/follow_up_controller.dart';
import 'package:gps_cielo/features/notifications/data/repositories/notification_repository.dart';

class _NoNotifications implements NotificationRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const uid = 'alice';

/// [count] status docs; doc `h00` is the newest. Every third is prayed.
Future<void> seedStatuses(FakeFirebaseFirestore db, int count) async {
  final start = DateTime(2026, 11, 1);
  for (var i = 0; i < count; i++) {
    final id = 'h${i.toString().padLeft(2, '0')}';
    await db.doc('users/$uid/household_status/$id').set({
      'isPrayed': i % 3 == 0,
      'isVisited': false,
      'isInvited': i % 3 != 0,
      'hasFollowUp': false,
      'residentName': 'Demo Household $id',
      'address': 'Demo',
      'updatedAt': Timestamp.fromDate(start.subtract(Duration(minutes: i))),
    });
  }
}

void main() {
  late FakeFirebaseFirestore db;
  late HouseholdRepository repository;

  setUp(() {
    db = FakeFirebaseFirestore();
    repository = HouseholdRepository(firestore: db);
  });

  group('HouseholdRepository.fetchStatusPage', () {
    test('pages 20 at a time, newest first, until none remain', () async {
      await seedStatuses(db, 45);
      final ids = <String>[];
      HouseholdSnapshot? cursor;
      final sizes = <int>[];
      final more = <bool>[];
      do {
        final page = await repository.fetchStatusPage(
          uid: uid,
          startAfter: cursor,
        );
        sizes.add(page.docs.length);
        more.add(page.hasMore);
        ids.addAll(page.docs.map((d) => d.id));
        cursor = page.cursor;
        if (!page.hasMore) break;
      } while (true);

      expect(sizes, [20, 20, 5]);
      expect(more, [true, true, false]);
      expect(ids.toSet().length, 45);
      expect(ids.first, 'h00');
      expect(ids.last, 'h44');
    });

    test('exactly 20 means one page and no "more"', () async {
      await seedStatuses(db, 20);
      final page = await repository.fetchStatusPage(uid: uid);
      expect(page.docs.length, 20);
      expect(page.hasMore, isFalse);
    });

    test('filters a tab by its status flag', () async {
      await seedStatuses(db, 45); // 15 prayed
      final first = await repository.fetchStatusPage(
        uid: uid,
        onlyWhere: 'isPrayed',
        limit: 10,
      );
      expect(first.docs.length, 10);
      expect(first.hasMore, isTrue);
      expect(first.docs.every((d) => d.data()!['isPrayed'] == true), isTrue);
      final second = await repository.fetchStatusPage(
        uid: uid,
        onlyWhere: 'isPrayed',
        limit: 10,
        startAfter: first.cursor,
      );
      expect(second.docs.length, 5);
      expect(second.hasMore, isFalse);
    });
  });

  group('FollowUpController', () {
    late HouseholdStore store;
    late FollowUpController controller;

    Future<void> settle() => Future<void>.delayed(Duration.zero);

    setUp(() async {
      Get.testMode = true;
      store = HouseholdStore(repository, _NoNotifications());
      // No home location, so no household (geo) query runs.
      await store.bindUser(
        UserModel(id: uid, fullName: 'A', email: 'a@example.com'),
      );
    });

    tearDown(Get.reset);

    Future<void> start() async {
      controller = Get.put(
        FollowUpController(FollowUpService(store, repository)),
      );
      await settle();
      await settle();
    }

    test('All is the first and default tab', () async {
      await start();
      expect(FollowUpTab.values.first, FollowUpTab.all);
      expect(controller.selectedTab.value, FollowUpTab.all);
    });

    test('loads 20, then the next 20, then the remaining 5', () async {
      await seedStatuses(db, 45);
      await start();
      expect(controller.filteredHouseholds.length, 20);
      expect(controller.hasMore.value, isTrue);

      await controller.loadMore();
      expect(controller.filteredHouseholds.length, 40);
      await controller.loadMore();
      expect(controller.filteredHouseholds.length, 45);
      expect(controller.hasMore.value, isFalse);

      await controller.loadMore(); // nothing left: no change
      expect(controller.filteredHouseholds.length, 45);
      expect(
        controller.filteredHouseholds.map((h) => h.number),
        List.generate(45, (i) => i + 1),
      );
    });

    test('switching tabs loads that tab from the first page', () async {
      await seedStatuses(db, 45);
      await start();
      controller.selectTab(FollowUpTab.prayed);
      await settle();
      await settle();
      expect(controller.filteredHouseholds.length, 15);
      expect(controller.filteredHouseholds.every((h) => h.isPrayed), isTrue);
      expect(controller.hasMore.value, isFalse);
    });

    test(
      'un-praying removes a household from the Prayed tab at once',
      () async {
        await seedStatuses(db, 6); // h00 and h03 prayed
        await start();
        controller.selectTab(FollowUpTab.prayed);
        await settle();
        await settle();
        expect(controller.filteredHouseholds.map((h) => h.id), ['h00', 'h03']);

        final h00 = controller.filteredHouseholds.first;
        await store.saveHousehold(h00.copyWith(isPrayed: false));
        await settle();
        expect(controller.filteredHouseholds.map((h) => h.id), ['h03']);
      },
    );

    test('a household changed after loading shows at the top', () async {
      await seedStatuses(db, 45);
      await start();
      expect(controller.filteredHouseholds.any((h) => h.id == 'h44'), isFalse);

      // h44 is on page 3 (not loaded here), but is visited now on another
      // device or screen: the session change listener brings it in.
      await db.doc('users/$uid/household_status/h44').update({
        'isVisited': true,
        'updatedAt': Timestamp.now(),
      });
      await settle();
      await settle();
      expect(controller.filteredHouseholds.first.id, 'h44');
      expect(controller.filteredHouseholds.length, 21);

      // Its own page later does not duplicate it.
      await controller.loadMore();
      await controller.loadMore();
      expect(
        controller.filteredHouseholds.where((h) => h.id == 'h44').length,
        1,
      );
    });

    test('tab counts come from server-side totals, not loaded pages', () async {
      await seedStatuses(db, 45); // 15 prayed, 30 invited
      await store.refreshCounts();
      await start();
      expect(controller.filteredHouseholds.length, 20); // one page read
      expect(controller.countFor(FollowUpTab.all), 45);
      expect(controller.countFor(FollowUpTab.prayed), 15);
      expect(controller.countFor(FollowUpTab.invited), 30);
      expect(controller.countFor(FollowUpTab.visited), 0);

      // A local change moves the totals at once.
      final first = controller.filteredHouseholds.firstWhere(
        (h) => !h.isVisited,
      );
      await store.saveHousehold(first.copyWith(isVisited: true));
      await settle();
      expect(controller.countFor(FollowUpTab.visited), 1);
    });
  });
}
