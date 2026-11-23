import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:gps_cielo/core/data/device_token_repository.dart';
import 'package:gps_cielo/core/models/user_model.dart';
import 'package:gps_cielo/core/services/push/app_badge.dart';
import 'package:gps_cielo/core/services/push/push_inbox.dart';
import 'package:gps_cielo/core/services/push/push_messaging_client.dart';
import 'package:gps_cielo/core/services/push/push_notification_service.dart';
import 'package:gps_cielo/features/notifications/data/models/notification_model.dart';
import 'package:gps_cielo/features/notifications/data/repositories/notification_repository.dart';
import 'package:gps_cielo/features/notifications/domain/services/notification_service.dart';
import 'package:gps_cielo/features/notifications/presentation/controllers/notification_controller.dart';
import 'package:gps_cielo/routes/app_routes.dart';

import 'push_notifications_test.dart' show FakeClient, user;

const _uid = 'me';

class _FakeUser implements User {
  _FakeUser(this.uid);
  @override
  final String uid;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeAuth implements FirebaseAuth {
  _FakeAuth(String? uid) : currentUser = uid == null ? null : _FakeUser(uid);
  @override
  User? currentUser;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Fields the Firestore rules allow on a client-created notification.
const _allowedKeys = {
  'title',
  'message',
  'type',
  'isRead',
  'actionRoute',
  'timestamp',
};
const _allowedTypes = {
  'prayerReminder',
  'followUpDue',
  'milestone',
  'scripture',
  'churchNews',
};

PushMessage push({
  String? id = '0:1794386733918895%8d530a03',
  String? title = 'Follow-up today',
  String? body = 'Visit the Rahman family',
  Map<String, dynamic> data = const {
    'type': 'followUpDue',
    'route': '/follow-up',
  },
}) => PushMessage(id: id, title: title, body: body, data: data);

void main() {
  late FakeFirebaseFirestore db;
  late PushInbox inbox;

  CollectionReference<Map<String, dynamic>> inboxOf(String uid) =>
      db.collection('users/$uid/notifications');

  Future<List<Map<String, dynamic>>> entries([String uid = _uid]) async =>
      (await inboxOf(uid).get()).docs.map((d) => d.data()).toList();

  setUp(() {
    Get.testMode = true;
    db = FakeFirebaseFirestore();
    inbox = PushInbox(firestore: db);
  });
  tearDown(Get.reset);

  group('PushInbox ids', () {
    test('a server notificationId is used as-is', () {
      expect(
        PushInbox.idFor(push(data: {'notificationId': 'abc_123-X'})),
        'abc_123-X',
      );
    });

    test('otherwise the FCM message id, made safe for Firestore', () {
      expect(
        PushInbox.idFor(push(id: '0:179/43%8d.ab')),
        'push_0_179_43_8d_ab',
      );
      // An invalid server id (slash) falls back to the message id.
      expect(
        PushInbox.idFor(push(id: 'm1', data: {'notificationId': 'a/b'})),
        'push_m1',
      );
    });

    test('no id at all: cannot be kept', () {
      expect(PushInbox.idFor(push(id: null)), isNull);
    });
  });

  group('PushInbox records', () {
    test('a received push is stored unread, within the rules', () async {
      await inbox.recordReceived(_uid, push());
      final all = await entries();
      expect(all, hasLength(1));
      final e = all.single;
      expect(e['title'], 'Follow-up today');
      expect(e['message'], 'Visit the Rahman family');
      expect(e['isRead'], isFalse);
      expect(e['type'], 'followUpDue');
      expect(e['actionRoute'], AppRoutes.followUp);
      expect(e['timestamp'], isA<Timestamp>());
      expect(_allowedKeys.containsAll(e.keys), isTrue, reason: '${e.keys}');
      expect(_allowedTypes, contains(e['type']));
    });

    test('the same push received twice is stored once', () async {
      await inbox.recordReceived(_uid, push());
      await inbox.recordReceived(_uid, push());
      expect(await entries(), hasLength(1));
    });

    test('tapping marks the stored push read', () async {
      await inbox.recordReceived(_uid, push());
      await inbox.recordOpened(_uid, push());
      final all = await entries();
      expect(all, hasLength(1));
      expect(all.single['isRead'], isTrue);
    });

    test('a tapped push that was never stored is added as read', () async {
      await inbox.recordOpened(_uid, push());
      final all = await entries();
      expect(all.single['isRead'], isTrue);
    });

    test('a server-written entry is reused, not duplicated', () async {
      await inboxOf(_uid).doc('srv_1').set({
        'title': 'From the server',
        'message': 'Original text',
        'type': 'churchNews',
        'isRead': false,
        'actionRoute': AppRoutes.notifications,
        'timestamp': Timestamp.now(),
      });
      final p = push(data: {'notificationId': 'srv_1'}, title: 'Other');
      await inbox.recordReceived(_uid, p);
      expect(await entries(), hasLength(1));
      await inbox.recordOpened(_uid, p);
      final e = (await inboxOf(_uid).doc('srv_1').get()).data()!;
      expect(e['isRead'], isTrue);
      expect(e['title'], 'From the server');
    });

    test('missing type and unknown route get safe defaults', () async {
      await inbox.recordReceived(
        _uid,
        push(data: {'route': '/delete-account'}),
      );
      final e = (await entries()).single;
      expect(e['type'], 'churchNews');
      expect(e['actionRoute'], AppRoutes.notifications);
    });

    test('over-long text is cut to the rules limits', () async {
      await inbox.recordReceived(
        _uid,
        push(title: 'T' * 500, body: 'B' * 5000),
      );
      final e = (await entries()).single;
      expect((e['title'] as String).length, PushInbox.maxTitle);
      expect((e['message'] as String).length, PushInbox.maxMessage);
    });

    test('a data-only message (nothing to show) is not stored', () async {
      await inbox.recordReceived(_uid, push(title: null, body: null));
      expect(await entries(), isEmpty);
    });
  });

  group('push service keeps pushes in the inbox', () {
    late FakeClient client;
    late Rxn<UserModel> current;
    late List<String> opened;

    Future<PushNotificationService> start() async {
      client = FakeClient()..status = PushPermission.authorized;
      current = Rxn<UserModel>();
      opened = [];
      final service = PushNotificationService(
        client,
        DeviceTokenRepository(firestore: db),
        current,
        platform: 'ios',
        showForegroundInApp: false,
        open: opened.add,
        inbox: inbox,
      );
      await service.start();
      return service;
    }

    test('a push received while the app is open counts as unread', () async {
      final service = await start();
      current.value = user(_uid);
      await service.onAppReady();
      client.foreground.add(push());
      await pumpEventQueue();
      final e = (await entries()).single;
      expect(e['isRead'], isFalse);
    });

    test('tapping a push opens its screen and marks it read', () async {
      final service = await start();
      current.value = user(_uid);
      await service.onAppReady();
      client.foreground.add(push());
      await pumpEventQueue();
      client.opened.add(push());
      await pumpEventQueue();
      expect(opened, [AppRoutes.followUp]);
      final all = await entries();
      expect(all, hasLength(1));
      expect(all.single['isRead'], isTrue);
    });

    test('a tap that launched the app is marked read after sign-in', () async {
      final service = await start();
      client.opened.add(push());
      await pumpEventQueue();
      expect(await entries(), isEmpty); // not signed in yet
      current.value = user(_uid);
      await service.onAppReady();
      expect(opened, [AppRoutes.followUp]);
      expect((await entries()).single['isRead'], isTrue);
    });

    test('a pending tap is forgotten on sign-out', () async {
      final service = await start();
      client.opened.add(push());
      await pumpEventQueue();
      await service.unregister(_uid);
      current.value = user(_uid);
      await service.onAppReady();
      expect(opened, isEmpty);
      expect(await entries(), isEmpty);
    });
  });

  group('unread count (Home bell badge)', () {
    test('follows new pushes, single reads and "mark all read"', () async {
      final repo = NotificationRepository(firestore: db, auth: _FakeAuth(_uid));
      final counts = <int>[];
      final sub = repo.watchUnreadCount().listen(counts.add);
      await pumpEventQueue();

      await inbox.recordReceived(_uid, push(id: 'a'));
      await inbox.recordReceived(_uid, push(id: 'b'));
      await inbox.recordReceived(_uid, push(id: 'c'));
      await pumpEventQueue();
      expect(counts.last, 3);

      await inbox.recordOpened(_uid, push(id: 'a'));
      await pumpEventQueue();
      expect(counts.last, 2);

      await repo.markAsRead('push_b');
      await pumpEventQueue();
      expect(counts.last, 1);

      await repo.markAllAsRead();
      await pumpEventQueue();
      expect(counts.last, 0);
      await sub.cancel();
    });

    test("another account's notifications are not counted", () async {
      await inbox.recordReceived('someone-else', push());
      final repo = NotificationRepository(firestore: db, auth: _FakeAuth(_uid));
      expect(await repo.watchUnreadCount().first, 0);
    });
  });

  group('inbox screen read / unread', () {
    late NotificationRepository repo;
    late NotificationController controller;

    Future<void> open() async {
      repo = NotificationRepository(firestore: db, auth: _FakeAuth(_uid));
      controller = NotificationController(NotificationService(repo));
      controller.onInit();
      await pumpEventQueue();
    }

    tearDown(() => controller.onClose());

    test('lists pushes newest first with their unread state', () async {
      await inbox.recordReceived(_uid, push(id: 'a', title: 'First'));
      await inbox.recordOpened(_uid, push(id: 'b', title: 'Second'));
      await open();
      expect(controller.notifications, hasLength(2));
      expect(controller.unreadCount, 1);
      final first = controller.notifications.firstWhere(
        (n) => n.title == 'First',
      );
      expect(first.isRead, isFalse);
      expect(first.actionRoute, AppRoutes.followUp);
      expect(first.type, NotificationType.followUpDue);
    });

    test('marking one read updates the list and Firestore', () async {
      await inbox.recordReceived(_uid, push(id: 'a'));
      await inbox.recordReceived(_uid, push(id: 'b'));
      await open();
      expect(controller.unreadCount, 2);
      await controller.markAsRead('push_a');
      await pumpEventQueue();
      expect(controller.unreadCount, 1);
      expect(
        (await inboxOf(_uid).doc('push_a').get()).data()!['isRead'],
        isTrue,
      );
    });

    test('the Unread filter shows only unread ones', () async {
      await inbox.recordReceived(_uid, push(id: 'a'));
      await inbox.recordOpened(_uid, push(id: 'b'));
      await open();
      controller.selectedFilter.value = NotificationFilter.unread;
      expect(controller.filteredNotifications.map((n) => n.id), ['push_a']);
    });

    test('"mark all read" clears every unread one', () async {
      for (final id in ['a', 'b', 'c']) {
        await inbox.recordReceived(_uid, push(id: id));
      }
      await open();
      await controller.markAllAsRead();
      await pumpEventQueue();
      expect(controller.unreadCount, 0);
      final docs = await entries();
      expect(docs.every((d) => d['isRead'] == true), isTrue);
    });
  });

  group('app icon badge', () {
    late Rxn<UserModel> current;
    late Map<String, StreamController<int>> unread;
    late List<int> badge;
    late AppBadgeSync sync;

    setUp(() {
      current = Rxn<UserModel>();
      unread = {};
      badge = [];
      sync = AppBadgeSync(
        currentUser: current,
        unreadCount: () =>
            (unread[current.value!.id] = StreamController<int>.broadcast())
                .stream,
        setBadge: (n) async => badge.add(n),
      )..start();
    });
    tearDown(() => sync.dispose());

    test('is cleared while signed out', () async {
      await pumpEventQueue();
      expect(badge, [0]);
    });

    test('shows the unread count and follows it', () async {
      current.value = user(_uid);
      await pumpEventQueue();
      unread[_uid]!.add(3);
      unread[_uid]!.add(2);
      await pumpEventQueue();
      expect(badge.last, 2);
    });

    test('clears on sign-out and follows the next account', () async {
      current.value = user(_uid);
      await pumpEventQueue();
      unread[_uid]!.add(4);
      await pumpEventQueue();
      current.value = null;
      await pumpEventQueue();
      expect(badge.last, 0);
      // The old account's stream no longer changes the badge.
      unread[_uid]!.add(9);
      current.value = user('other');
      await pumpEventQueue();
      unread['other']!.add(1);
      await pumpEventQueue();
      expect(badge.last, 1);
      expect(badge, isNot(contains(9)));
    });

    test('a profile update for the same account does not resubscribe', () {
      current.value = user(_uid);
      final first = unread[_uid];
      current.value = user(_uid).copyWith(fullName: 'New name');
      expect(unread[_uid], same(first));
    });
  });
}
