import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

/// Whether the user lets the app show notifications.
enum PushPermission { notDetermined, authorized, provisional, denied }

/// A received push message, independent of the Firebase types.
class PushMessage {
  final String? id;
  final String? title;
  final String? body;
  final Map<String, dynamic> data;

  const PushMessage({this.id, this.title, this.body, this.data = const {}});

  factory PushMessage.fromRemote(RemoteMessage message) => PushMessage(
    id: message.messageId,
    title: message.notification?.title,
    body: message.notification?.body,
    data: message.data,
  );
}

/// The Firebase Messaging calls the app uses, behind an interface so the
/// notification logic can be tested without a device.
abstract class PushMessagingClient {
  Future<PushPermission> permission();
  Future<PushPermission> requestPermission();

  /// The FCM registration token, or null when it is not available yet (on
  /// iOS it needs the APNs token first).
  Future<String?> getToken();
  Stream<String> get onTokenRefresh;
  Future<void> deleteToken();

  /// The notification the app was launched from by a tap, if any.
  Future<PushMessage?> initialMessage();

  /// Messages received while the app is in the foreground.
  Stream<PushMessage> get onForegroundMessage;

  /// Notifications tapped while the app was in the background.
  Stream<PushMessage> get onOpenedApp;
}

class FirebasePushMessagingClient implements PushMessagingClient {
  final FirebaseMessaging _messaging;

  FirebasePushMessagingClient({FirebaseMessaging? messaging})
    : _messaging = messaging ?? FirebaseMessaging.instance;

  static PushPermission _map(AuthorizationStatus status) => switch (status) {
    AuthorizationStatus.authorized => PushPermission.authorized,
    AuthorizationStatus.provisional => PushPermission.provisional,
    AuthorizationStatus.denied ||
    AuthorizationStatus.deniedPermanently => PushPermission.denied,
    AuthorizationStatus.notDetermined => PushPermission.notDetermined,
  };

  /// iOS: show the system banner, sound and badge for notifications that
  /// arrive while the app is open (the app adds nothing of its own there,
  /// so nothing is shown twice).
  Future<void> configureForeground() {
    return _messaging.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );
  }

  @override
  Future<PushPermission> permission() async =>
      _map((await _messaging.getNotificationSettings()).authorizationStatus);

  @override
  Future<PushPermission> requestPermission() async => _map(
    (await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    )).authorizationStatus,
  );

  @override
  Future<String?> getToken() async {
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      // The APNs token can arrive a little after launch; FCM cannot make a
      // token without it.
      String? apns;
      for (var i = 0; i < 10 && apns == null; i++) {
        apns = await _messaging.getAPNSToken();
        if (apns == null) {
          await Future<void>.delayed(const Duration(seconds: 1));
        }
      }
      if (apns == null) return null; // tried again on the next start
    }
    return _messaging.getToken();
  }

  @override
  Stream<String> get onTokenRefresh => _messaging.onTokenRefresh;

  @override
  Future<void> deleteToken() => _messaging.deleteToken();

  @override
  Future<PushMessage?> initialMessage() async {
    final message = await _messaging.getInitialMessage();
    return message == null ? null : PushMessage.fromRemote(message);
  }

  @override
  Stream<PushMessage> get onForegroundMessage =>
      FirebaseMessaging.onMessage.map(PushMessage.fromRemote);

  @override
  Stream<PushMessage> get onOpenedApp =>
      FirebaseMessaging.onMessageOpenedApp.map(PushMessage.fromRemote);
}
