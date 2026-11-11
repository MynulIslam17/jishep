import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:gps_cielo/core/data/device_token_repository.dart';
import 'package:gps_cielo/core/models/user_model.dart';
import 'package:gps_cielo/core/services/push/push_inbox.dart';
import 'package:gps_cielo/core/services/push/push_messaging_client.dart';
import 'package:gps_cielo/core/services/push/push_payload.dart';
import 'package:gps_cielo/core/utils/show_snackbar.dart';
import 'package:gps_cielo/features/main_nav/presentation/controllers/main_nav_controller.dart';
import 'package:gps_cielo/features/main_nav/presentation/models/main_nav_destination.dart';
import 'package:gps_cielo/routes/app_routes.dart';

/// Push notifications (Firebase Cloud Messaging) for the signed-in user.
///
///  * **Permission** is asked once, when the main app first opens after
///    sign-in (never on the sign-in screens). A user who already answered is
///    not asked again.
///  * **Device token**: while signed in with permission, this device's FCM
///    token is stored at `users/{uid}/devices/{token}` (one document per
///    token, so no duplicates; one per device, so several devices work). A
///    refreshed token replaces the old one. Before sign-out or account
///    deletion the document is removed and the token deleted, so the next
///    person on this phone never gets the previous user's notifications.
///  * **Foreground**: iOS shows the system banner; Android shows an in-app
///    banner (Android shows nothing on its own while the app is open).
///  * **Taps** open the screen named by the payload ([PushPayload]); a tap
///    that launches the app waits until the user is signed in and the main
///    app is on screen.
///  * **Inbox**: pushes are kept in the in-app inbox ([PushInbox]) so the
///    unread badge counts them: received ones unread, tapped ones read.
///
/// Nothing here changes prayers, visits or any household status.
class PushNotificationService extends GetxService {
  final PushMessagingClient _client;
  final DeviceTokenRepository _tokens;
  final Rxn<UserModel> _currentUser;

  /// "ios" or "android", stored with the token.
  final String platform;

  /// Shows a message that arrived while the app is open, when the system
  /// does not (Android).
  final bool showForegroundInApp;

  /// Opens a screen; replaceable in tests.
  final void Function(String route) _open;

  /// Where pushes are kept for the in-app inbox (null: not kept).
  final PushInbox? _inbox;

  PushNotificationService(
    this._client,
    this._tokens,
    this._currentUser, {
    required this.platform,
    required this.showForegroundInApp,
    void Function(String route)? open,
    PushInbox? inbox,
  }) : _open = open ?? openAppRoute,
       _inbox = inbox;

  /// The account the stored token belongs to, and the token.
  String? _uid;
  String? _token;

  /// True once the main app is on screen for a signed-in user.
  bool _appReady = false;

  /// A tapped notification waiting for the app to be ready.
  PushPayload? pendingTap;
  PushMessage? _pendingTapMessage;

  /// Message ids already opened (the launch message can be reported twice).
  final Set<String> _openedIds = {};

  final List<StreamSubscription<dynamic>> _subscriptions = [];
  Worker? _userWorker;

  String? get registeredToken => _token;

  /// Starts listening. Call once, after Firebase is initialized.
  Future<void> start() async {
    _subscriptions.addAll([
      _client.onTokenRefresh.listen(_onTokenRefresh, onError: (_) {}),
      _client.onForegroundMessage.listen(_onForeground, onError: (_) {}),
      _client.onOpenedApp.listen(_onTap, onError: (_) {}),
    ]);
    _userWorker = ever<UserModel?>(_currentUser, _onUser);
    try {
      final launch = await _client.initialMessage();
      if (launch != null) _onTap(launch);
    } catch (_) {}
  }

  /// The main app is on screen for a signed-in user: ask for permission the
  /// first time, register this device, and open a waiting notification.
  Future<void> onAppReady() async {
    final user = _currentUser.value;
    if (user == null) return;
    _appReady = true;
    try {
      var permission = await _client.permission();
      if (permission == PushPermission.notDetermined) {
        permission = await _client.requestPermission();
      }
      if (permission == PushPermission.authorized ||
          permission == PushPermission.provisional) {
        await _register(user.id);
      }
    } catch (_) {
      // Notifications are optional; the app works without them.
    }
    final tap = pendingTap;
    final tapMessage = _pendingTapMessage;
    _pendingTapMessage = null;
    if (tap != null) {
      pendingTap = null;
      if (tapMessage != null) await _keep(user.id, tapMessage, opened: true);
      _open(tap.route);
    }
  }

  /// Removes this device from [uid] before signing out or deleting the
  /// account, while the user can still write their own data.
  Future<void> unregister(String uid) async {
    _appReady = false;
    pendingTap = null;
    _pendingTapMessage = null;
    final token = _token;
    _token = null;
    _uid = null;
    if (token != null) {
      try {
        await _tokens
            .delete(uid: uid, token: token)
            .timeout(const Duration(seconds: 5));
      } catch (_) {}
    }
    try {
      // A new token is made for the next account on this device.
      await _client.deleteToken().timeout(const Duration(seconds: 5));
    } catch (_) {}
  }

  void _onUser(UserModel? user) {
    if (user == null) {
      _appReady = false;
      _uid = null;
      _token = null;
      return;
    }
    // A profile update for the same account changes nothing here.
    if (user.id == _uid || !_appReady) return;
    unawaited(_registerIfAllowed(user.id));
  }

  Future<void> _registerIfAllowed(String uid) async {
    try {
      final permission = await _client.permission();
      if (permission == PushPermission.authorized ||
          permission == PushPermission.provisional) {
        await _register(uid);
      }
    } catch (_) {}
  }

  Future<void> _register(String uid) async {
    final token = await _client.getToken();
    if (token == null || token.isEmpty) return;
    if (uid == _uid && token == _token) return;
    await _tokens.save(uid: uid, token: token, platform: platform);
    _uid = uid;
    _token = token;
    if (kDebugMode) {
      debugPrint('FCM: device registered (${token.length} chars)');
    }
  }

  Future<void> _onTokenRefresh(String token) async {
    final uid = _uid;
    if (uid == null || token == _token) return;
    final old = _token;
    try {
      await _tokens.save(uid: uid, token: token, platform: platform);
      _token = token;
      if (old != null) await _tokens.delete(uid: uid, token: old);
    } catch (_) {}
  }

  void _onForeground(PushMessage message) {
    final uid = _currentUser.value?.id;
    if (uid != null) unawaited(_keep(uid, message, opened: false));
    if (!showForegroundInApp) return; // the system shows it (iOS)
    final title = message.title;
    final body = message.body;
    if ((title ?? '').isEmpty && (body ?? '').isEmpty) return;
    SnackbarService.showInfo(title ?? 'GPS Para El Cielo', body ?? '');
  }

  void _onTap(PushMessage message) {
    final id = message.id;
    if (id != null && !_openedIds.add(id)) return;
    final payload = PushPayload.fromData(message.data);
    final uid = _currentUser.value?.id;
    if (_appReady && uid != null) {
      unawaited(_keep(uid, message, opened: true));
      _open(payload.route);
    } else {
      pendingTap = payload;
      _pendingTapMessage = message;
    }
  }

  /// Adds [message] to [uid]'s inbox (read when [opened]). Never throws:
  /// the notification itself was already shown.
  Future<void> _keep(
    String uid,
    PushMessage message, {
    required bool opened,
  }) async {
    final inbox = _inbox;
    if (inbox == null) return;
    try {
      await (opened
              ? inbox.recordOpened(uid, message)
              : inbox.recordReceived(uid, message))
          .timeout(const Duration(seconds: 10));
    } catch (_) {}
  }

  /// Opens [route]: a main tab is selected inside the main app (closing any
  /// page above it); the inbox opens on top.
  static void openAppRoute(String route) {
    if (!Get.isRegistered<MainNavController>()) return;
    if (Get.currentRoute != AppRoutes.mainNav) {
      Get.until((r) => r.settings.name == AppRoutes.mainNav || r.isFirst);
    }
    final tab = tabRoutes[route];
    if (tab != null) {
      Get.find<MainNavController>().changeDestination(tab);
    } else {
      Get.toNamed(route);
    }
  }

  static const Map<String, MainNavDestination> tabRoutes = {
    AppRoutes.home: MainNavDestination.home,
    AppRoutes.neighborhood: MainNavDestination.neighborhood,
    AppRoutes.prayerList: MainNavDestination.prayerList,
    AppRoutes.followUp: MainNavDestination.followUp,
    AppRoutes.profile: MainNavDestination.profile,
  };

  @override
  void onClose() {
    for (final s in _subscriptions) {
      s.cancel();
    }
    _userWorker?.dispose();
    super.onClose();
  }
}
