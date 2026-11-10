import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:gps_cielo/features/notifications/data/repositories/notification_repository.dart';
import 'package:gps_cielo/features/notifications/domain/services/notification_service.dart';
import 'package:gps_cielo/features/notifications/presentation/controllers/notification_controller.dart';

class _User implements User {
  @override
  String get uid => 'u1';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Auth implements FirebaseAuth {
  @override
  User? get currentUser => _User();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// [n] notifications, n_0 the newest; every third one unread.
Future<FakeFirebaseFirestore> seed(int n) async {
  final db = FakeFirebaseFirestore();
  final base = DateTime(2026, 1, 1);
  for (var i = 0; i < n; i++) {
    await db.collection('users/u1/notifications').doc('n_$i').set({
      'title': 'Note $i',
      'message': 'm',
      'type': 'prayerReminder',
      'isRead': i % 3 != 0,
      'timestamp': Timestamp.fromDate(base.subtract(Duration(minutes: i))),
    });
  }
  return db;
}

void main() {
  setUp(() => Get.testMode = true);
  tearDown(Get.reset);

  NotificationController make(FakeFirebaseFirestore db) {
    final repo = NotificationRepository(firestore: db, auth: _Auth());
    return NotificationController(NotificationService(repo))..onInit();
  }

  test('listens to the newest 30 and reads older pages on demand', () async {
    final db = await seed(75);
    final c = make(db);
    await pumpEventQueue();

    expect(c.notifications.length, NotificationRepository.pageSize);
    expect(c.notifications.first.id, 'n_0');
    expect(c.notifications.last.id, 'n_29');
    expect(c.hasMore.value, isTrue);

    await c.loadMore();
    expect(c.notifications.length, 60);
    await c.loadMore();
    expect(c.notifications.length, 75);
    expect(c.hasMore.value, isFalse);

    final ids = c.notifications.map((n) => n.id).toList();
    expect(ids, [for (var i = 0; i < 75; i++) 'n_$i']); // newest first, once
    c.onClose();
  });

  test(
    'a new notification arrives live without duplicating older pages',
    () async {
      final db = await seed(45);
      final c = make(db);
      await pumpEventQueue();
      await c.loadMore();
      expect(c.notifications.length, 45);

      await db.collection('users/u1/notifications').doc('new').set({
        'title': 'New',
        'message': 'm',
        'type': 'milestone',
        'isRead': false,
        'timestamp': Timestamp.fromDate(DateTime(2026, 2, 1)),
      });
      await pumpEventQueue();

      // n_29 was pushed out of the live 30 but is still listed; nothing is
      // missing or listed twice.
      final ids = c.notifications.map((n) => n.id).toList();
      expect(ids, ['new', for (var i = 0; i < 45; i++) 'n_$i']);
      c.onClose();
    },
  );

  test('the unread badge count is capped at 100', () async {
    final db = await seed(330); // 110 unread
    final repo = NotificationRepository(firestore: db, auth: _Auth());
    expect(await repo.watchUnreadCount().first, 100);
  });

  test('mark all read and clear all work past one batch', () async {
    final db = await seed(1000); // 334 unread
    final repo = NotificationRepository(firestore: db, auth: _Auth());
    await repo.markAllAsRead();
    final unread = await db
        .collection('users/u1/notifications')
        .where('isRead', isEqualTo: false)
        .get();
    expect(unread.docs, isEmpty);

    await repo.clearAllNotifications();
    final all = await db.collection('users/u1/notifications').get();
    expect(all.docs, isEmpty);
  });
}
