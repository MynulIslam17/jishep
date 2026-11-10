import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:gps_cielo/core/utils/firebase_error_mapper.dart';
import 'package:gps_cielo/core/utils/show_snackbar.dart';
import 'package:gps_cielo/features/auth/domain/services/auth_service.dart';
import 'package:gps_cielo/features/auth/presentation/controllers/auth_controller.dart';

/// Waits on the Verify Email screen until the user clicks the link.
///
/// Firebase has no live event for "email verified" (the link is opened in a
/// browser, outside the app), so the account is reloaded:
/// - right away when the app returns to the foreground (back from the mail
///   app) — the moment it usually happens;
/// - quietly in the background while the screen is open: every
///   [fastInterval] for the first [fastPhase], then every [slowInterval],
///   stopping after [maxAutoCheck] (the button still works after that);
/// - when the user taps "I've verified my email".
/// Background checks never show a loader; only the button tap does.
class VerifyEmailController extends GetxController with WidgetsBindingObserver {
  VerifyEmailController(
    this._authService,
    this._authController, {
    this.fastInterval = const Duration(seconds: 3),
    this.slowInterval = const Duration(seconds: 10),
    this.fastPhase = const Duration(minutes: 1),
    this.maxAutoCheck = const Duration(minutes: 10),
  });

  final AuthService _authService;
  final AuthController _authController;
  final Duration fastInterval;
  final Duration slowInterval;
  final Duration fastPhase;
  final Duration maxAutoCheck;

  /// Seconds before the link can be sent again.
  static const int resendCooldown = 60;

  /// The user tapped "I've verified" and we're checking (button loader).
  final isChecking = false.obs;
  final isResending = false.obs;

  /// Verified: shown briefly while the app moves on.
  final isVerified = false.obs;

  /// Background checks are running (status line, no loader on buttons).
  final isAutoChecking = false.obs;
  final cooldown = 0.obs;

  /// True once a link is on its way in this session.
  final linkSent = false.obs;

  Timer? _poll;
  Timer? _cooldownTimer;
  final _sinceStart = Stopwatch();
  bool _busy = false;
  bool _leaving = false;
  bool _foreground = true;

  String get email => _authService.firebaseUser?.email ?? '';

  @override
  void onInit() {
    super.onInit();
    final args = Get.arguments;
    final sent = args is Map && args['sent'] == true;
    linkSent.value = sent;
    if (sent) _startCooldown();
    WidgetsBinding.instance.addObserver(this);
    _sinceStart.start();
    _scheduleNext();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _foreground = true;
      // Back from the mail app: check now and give auto-checks a fresh run.
      _sinceStart
        ..reset()
        ..start();
      _check(manual: false);
      _scheduleNext();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      // No polling while the app is in the background.
      _foreground = false;
      _poll?.cancel();
    }
  }

  void _scheduleNext() {
    _poll?.cancel();
    if (_leaving || !_foreground) return;
    final elapsed = _sinceStart.elapsed;
    if (elapsed >= maxAutoCheck) {
      isAutoChecking.value = false;
      return;
    }
    isAutoChecking.value = true;
    final wait = elapsed < fastPhase ? fastInterval : slowInterval;
    _poll = Timer(wait, () async {
      await _check(manual: false);
      _scheduleNext();
    });
  }

  /// "I've verified my email".
  Future<void> check() => _check(manual: true);

  Future<void> _check({required bool manual}) async {
    if (_leaving) return;
    if (_busy) {
      // A background check is in flight; show the loader for the tap.
      if (manual) isChecking.value = true;
      return;
    }
    _busy = true;
    if (manual) isChecking.value = true;
    try {
      if (await _authService.checkEmailVerified()) {
        await _continue();
      } else if (manual) {
        SnackbarService.showInfo(
          'Not verified yet',
          'Open the email we sent to $email and tap the link, then come '
              'back here.',
        );
      }
    } catch (error) {
      // Background checks stay quiet (e.g. briefly offline).
      if (manual) {
        SnackbarService.showError(
          'Could not check',
          FirebaseErrorMapper.message(error),
        );
      }
    } finally {
      _busy = false;
      if (!_leaving) isChecking.value = false;
    }
  }

  Future<void> _continue() async {
    _leaving = true;
    _poll?.cancel();
    isAutoChecking.value = false;
    isVerified.value = true;
    final profile = await _authController.loadCurrentProfile();
    if (profile == null) {
      _leaving = false;
      isVerified.value = false;
      _scheduleNext();
      return;
    }
    // Let the "Verified" state show for a moment before moving on.
    await Future<void>.delayed(const Duration(milliseconds: 700));
    _authController.routeAfterSignIn(profile);
  }

  Future<void> resend() async {
    if (isResending.value || cooldown.value > 0 || _leaving) return;
    isResending.value = true;
    try {
      await _authService.sendEmailVerification();
      linkSent.value = true;
      _startCooldown();
      // A new link restarts the automatic checks.
      _sinceStart
        ..reset()
        ..start();
      _scheduleNext();
      SnackbarService.showSuccess(
        'Email sent',
        'A new link is on its way to $email.',
      );
    } catch (error) {
      SnackbarService.showError(
        'Email not sent',
        FirebaseErrorMapper.message(error),
      );
    } finally {
      isResending.value = false;
    }
  }

  void _startCooldown() {
    cooldown.value = resendCooldown;
    _cooldownTimer?.cancel();
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (cooldown.value <= 1) {
        cooldown.value = 0;
        t.cancel();
      } else {
        cooldown.value--;
      }
    });
  }

  /// Wrong address, or another account: start again from Sign In.
  Future<void> signOut() async {
    _leaving = true;
    _poll?.cancel();
    await _authController.signOut();
  }

  @override
  void onClose() {
    WidgetsBinding.instance.removeObserver(this);
    _poll?.cancel();
    _cooldownTimer?.cancel();
    super.onClose();
  }
}
