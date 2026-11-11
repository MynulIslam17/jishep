import 'dart:async';

import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:gps_cielo/core/models/user_model.dart';

/// Sets the number on the app icon (iOS; see AppDelegate.swift). Android
/// launchers show their own dot from the notifications in the tray, so this
/// does nothing there.
class AppBadge {
  static const MethodChannel _channel = MethodChannel('gps_cielo/app_badge');

  Future<void> setCount(int count) async {
    try {
      await _channel.invokeMethod<void>('setCount', count < 0 ? 0 : count);
    } on MissingPluginException {
      // Not iOS.
    } on PlatformException {
      // Badges not allowed; nothing to do.
    }
  }
}

/// Keeps the app icon badge equal to the signed-in user's unread
/// notifications, and clears it on sign-out.
class AppBadgeSync {
  AppBadgeSync({
    required Rxn<UserModel> currentUser,
    required Stream<int> Function() unreadCount,
    required Future<void> Function(int count) setBadge,
  }) : _currentUser = currentUser,
       _unreadCount = unreadCount,
       _setBadge = setBadge;

  final Rxn<UserModel> _currentUser;
  final Stream<int> Function() _unreadCount;
  final Future<void> Function(int count) _setBadge;

  Worker? _worker;
  StreamSubscription<int>? _subscription;
  String? _uid;
  bool _applied = false;

  void start() {
    _worker = ever<UserModel?>(_currentUser, _onUser);
    _onUser(_currentUser.value);
  }

  void _onUser(UserModel? user) {
    final uid = user?.id;
    // A profile update for the same account changes nothing.
    if (_applied && uid == _uid) return;
    _applied = true;
    _uid = uid;
    _subscription?.cancel();
    _subscription = null;
    if (uid == null) {
      unawaited(_safeSet(0));
      return;
    }
    _subscription = _unreadCount().listen(
      (count) => unawaited(_safeSet(count)),
      onError: (_) {},
    );
  }

  Future<void> _safeSet(int count) async {
    try {
      await _setBadge(count);
    } catch (_) {}
  }

  void dispose() {
    _worker?.dispose();
    _subscription?.cancel();
  }
}
