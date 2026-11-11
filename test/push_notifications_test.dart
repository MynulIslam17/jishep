import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:gps_cielo/core/data/device_token_repository.dart';
import 'package:gps_cielo/core/models/user_model.dart';
import 'package:gps_cielo/core/services/push/push_messaging_client.dart';
import 'package:gps_cielo/core/services/push/push_notification_service.dart';
import 'package:gps_cielo/core/services/push/push_payload.dart';
import 'package:gps_cielo/features/notifications/data/models/notification_model.dart';
import 'package:gps_cielo/routes/app_routes.dart';

class FakeClient implements PushMessagingClient {
  PushPermission status = PushPermission.notDetermined;
  PushPermission answer = PushPermission.authorized;
  int permissionRequests = 0;
  String? token = 'token-1';
  int deletedTokens = 0;
  PushMessage? launch;
  final refresh = StreamController<String>.broadcast();
  final foreground = StreamController<PushMessage>.broadcast();
  final opened = StreamController<PushMessage>.broadcast();

  @override
  Future<PushPermission> permission() async => status;

  @override
  Future<PushPermission> requestPermission() async {
    permissionRequests++;
    status = answer;
    return answer;
  }

  @override
  Future<String?> getToken() async => token;

  @override
  Stream<String> get onTokenRefresh => refresh.stream;

  @override
  Future<void> deleteToken() async {
    deletedTokens++;
    token = 'token-after-delete';
  }

  @override
  Future<PushMessage?> initialMessage() async => launch;

  @override
  Stream<PushMessage> get onForegroundMessage => foreground.stream;

  @override
  Stream<PushMessage> get onOpenedApp => opened.stream;
}

UserModel user(String id) => UserModel(id: id, fullName: id, email: '$id@x.io');

void main() {
  group('PushPayload', () {
    test('a known type opens its screen', () {
      final p = PushPayload.fromData({'type': 'prayerReminder'});
      expect(p.type, NotificationType.prayerReminder);
      expect(p.route, AppRoutes.prayerList);
      expect(
        PushPayload.fromData({'type': 'followUpDue'}).route,
        AppRoutes.followUp,
      );
    });

    test('an allowed route wins over the type default', () {
      final p = PushPayload.fromData({
        'type': 'prayerReminder',
        'route': AppRoutes.neighborhood,
        'householdId': 'demo_bd_001',
      });
      expect(p.route, AppRoutes.neighborhood);
      expect(p.householdId, 'demo_bd_001');
    });

    test('unknown or unsafe routes fall back to the inbox', () {
      for (final route in [
        '/delete-account',
        AppRoutes.signIn,
        AppRoutes.donation,
        'https://evil.example',
        '',
      ]) {
        expect(
          PushPayload.fromData({'route': route}).route,
          AppRoutes.notifications,
          reason: route,
        );
      }
      expect(PushPayload.fromData(const {}).route, AppRoutes.notifications);
      expect(PushPayload.fromData({'type': 'nonsense'}).type, isNull);
    });

    test('an oversized household id is dropped', () {
      final p = PushPayload.fromData({'householdId': 'x' * 500});
      expect(p.householdId, isNull);
    });
  });

  group('DeviceTokenRepository', () {
    test('one document per token, removed on delete', () async {
      final db = FakeFirebaseFirestore();
      final repo = DeviceTokenRepository(firestore: db);
      await repo.save(uid: 'alice', token: 't1', platform: 'ios');
      await repo.save(uid: 'alice', token: 't1', platform: 'ios');
      await repo.save(uid: 'alice', token: 't2', platform: 'android');
      final devices = await db.collection('users/alice/devices').get();
      expect(devices.docs.map((d) => d.id), unorderedEquals(['t1', 't2']));
      expect(devices.docs.first.data()['token'], devices.docs.first.id);

      await repo.delete(uid: 'alice', token: 't1');
      final left = await db.collection('users/alice/devices').get();
      expect(left.docs.map((d) => d.id), ['t2']);
    });
  });

  group('PushNotificationService', () {
    late FakeClient client;
    late FakeFirebaseFirestore db;
    late Rxn<UserModel> current;
    late List<String> opened;
    late PushNotificationService service;

    Future<List<String>> devicesOf(String uid) async =>
        (await db.collection('users/$uid/devices').get()).docs
            .map((d) => d.id)
            .toList();

    PushNotificationService make({bool android = false}) =>
        PushNotificationService(
          client,
          DeviceTokenRepository(firestore: db),
          current,
          platform: android ? 'android' : 'ios',
          showForegroundInApp: android,
          open: opened.add,
        );

    setUp(() async {
      Get.testMode = true;
      client = FakeClient();
      db = FakeFirebaseFirestore();
      current = Rxn<UserModel>();
      opened = [];
      service = make();
    });

    tearDown(() => service.onClose());

    test('asks for permission once, then registers this device', () async {
      await service.start();
      current.value = user('alice');
      await service.onAppReady();
      expect(client.permissionRequests, 1);
      expect(await devicesOf('alice'), ['token-1']);

      // Opening the app again never asks again.
      await service.onAppReady();
      expect(client.permissionRequests, 1);
      expect(await devicesOf('alice'), ['token-1']);
    });

    test('nothing is asked or stored before sign-in', () async {
      await service.start();
      await service.onAppReady();
      expect(client.permissionRequests, 0);
      expect(db.dump(), isNot(contains('devices')));
    });

    test('a denied permission is respected: no prompt, no token', () async {
      client.status = PushPermission.denied;
      await service.start();
      current.value = user('alice');
      await service.onAppReady();
      expect(client.permissionRequests, 0);
      expect(await devicesOf('alice'), isEmpty);
    });

    test('declining the prompt stores nothing', () async {
      client.answer = PushPermission.denied;
      await service.start();
      current.value = user('alice');
      await service.onAppReady();
      expect(client.permissionRequests, 1);
      expect(await devicesOf('alice'), isEmpty);
    });

    test('provisional (quiet) permission still registers', () async {
      client.status = PushPermission.provisional;
      await service.start();
      current.value = user('alice');
      await service.onAppReady();
      expect(await devicesOf('alice'), ['token-1']);
    });

    test('no token yet (APNs not ready) is retried next time', () async {
      client.token = null;
      await service.start();
      current.value = user('alice');
      await service.onAppReady();
      expect(await devicesOf('alice'), isEmpty);
      client.token = 'token-late';
      await service.onAppReady();
      expect(await devicesOf('alice'), ['token-late']);
    });

    test('a refreshed token replaces the old one', () async {
      await service.start();
      current.value = user('alice');
      await service.onAppReady();
      client.refresh.add('token-2');
      await pumpEventQueue();
      expect(await devicesOf('alice'), ['token-2']);
      expect(service.registeredToken, 'token-2');
    });

    test('sign-out removes the device and deletes the token', () async {
      await service.start();
      current.value = user('alice');
      await service.onAppReady();
      await service.unregister('alice');
      expect(await devicesOf('alice'), isEmpty);
      expect(client.deletedTokens, 1);

      // The next account on this phone gets its own token only.
      current.value = null;
      current.value = user('bob');
      await service.onAppReady();
      expect(await devicesOf('bob'), ['token-after-delete']);
      expect(await devicesOf('alice'), isEmpty);
    });

    test('a tap while running opens its screen', () async {
      await service.start();
      current.value = user('alice');
      await service.onAppReady();
      client.opened.add(
        const PushMessage(id: 'm1', data: {'type': 'followUpDue'}),
      );
      await pumpEventQueue();
      expect(opened, [AppRoutes.followUp]);
    });

    test('a tap that launched the app waits for sign-in, then opens', () async {
      client.launch = const PushMessage(
        id: 'm1',
        data: {'type': 'prayerReminder'},
      );
      await service.start();
      expect(opened, isEmpty);
      expect(service.pendingTap?.route, AppRoutes.prayerList);

      current.value = user('alice');
      await service.onAppReady();
      expect(opened, [AppRoutes.prayerList]);
      expect(service.pendingTap, isNull);
    });

    test('the same notification is opened only once', () async {
      client.launch = const PushMessage(id: 'm1', data: {});
      await service.start();
      current.value = user('alice');
      await service.onAppReady();
      client.opened.add(const PushMessage(id: 'm1', data: {}));
      await pumpEventQueue();
      expect(opened, [AppRoutes.notifications]);
    });

    test('a pending tap is dropped on sign-out', () async {
      client.launch = const PushMessage(id: 'm1', data: {});
      await service.start();
      await service.unregister('alice');
      current.value = user('bob');
      await service.onAppReady();
      expect(opened, isEmpty);
    });
  });
}
