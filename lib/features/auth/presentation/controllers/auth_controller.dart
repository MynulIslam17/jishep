import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:gps_cielo/core/data/user_repository.dart';
import 'package:gps_cielo/core/models/user_model.dart';
import 'package:gps_cielo/core/services/household_store.dart';
import 'package:gps_cielo/core/utils/firebase_error_mapper.dart';
import 'package:gps_cielo/core/utils/show_snackbar.dart';
import 'package:gps_cielo/features/auth/data/repositories/auth_repository.dart';
import 'package:gps_cielo/features/auth/domain/services/auth_service.dart';
import 'package:gps_cielo/routes/app_routes.dart';
import 'package:gps_cielo/shared/widgets/dialogs/app_loading_dialog.dart';

/// Global [AuthController] tracks the Firebase session and keeps the signed-in
/// user's Firestore profile in [currentUser].
///
/// Registered as a permanent singleton in [AppBinding].
class AuthController extends GetxController {
  final AuthService _authService;
  final UserRepository _userRepository;
  final HouseholdStore _householdStore;

  AuthController(this._authService, this._userRepository, this._householdStore);

  /// Live profile of the signed-in user (null when signed out).
  final currentUser = Rxn<UserModel>();

  StreamSubscription<User?>? _authSubscription;

  /// Run before signing out or deleting the account, while the user can
  /// still write their own data (e.g. removing this device's push token).
  final List<Future<void> Function(String uid)> _beforeSignOut = [];

  void addBeforeSignOut(Future<void> Function(String uid) hook) =>
      _beforeSignOut.add(hook);

  Future<void> _runBeforeSignOut() async {
    final uid = _authService.firebaseUser?.uid ?? currentUser.value?.id;
    if (uid == null) return;
    for (final hook in _beforeSignOut) {
      try {
        await hook(uid);
      } catch (_) {}
    }
  }

  StreamSubscription<UserModel?>? _profileSubscription;

  bool get isAuthenticated => _authService.firebaseUser != null;

  @override
  void onInit() {
    super.onInit();
    _authSubscription = _authService.authStateChanges().listen(_onAuthChanged);
  }

  void _onAuthChanged(User? user) {
    _profileSubscription?.cancel();
    _profileSubscription = null;

    if (user == null) {
      // signOut clears local data once the signed-in screens are gone.
      if (isSigningOut.value) return;
      currentUser.value = null;
      _householdStore.clear();
      return;
    }

    // Another account signed in: drop the previous account's cached data.
    if (currentUser.value != null && currentUser.value!.id != user.uid) {
      currentUser.value = null;
      _householdStore.clear();
    }

    _profileSubscription = _userRepository.watchUser(user.uid).listen((
      profile,
    ) {
      if (profile == null) return;
      currentUser.value = profile;
      _householdStore.bindUser(profile);
      _syncConfirmedEmail(user.uid, profile);
    }, onError: (_) {});
  }

  /// After the user confirms an email change from the verification link,
  /// Firebase Auth holds the new address; copy it to the profile.
  void _syncConfirmedEmail(String uid, UserModel profile) {
    final authUser = _authService.firebaseUser;
    final authEmail = authUser?.email?.trim();
    if (authUser == null || authUser.uid != uid) return;
    if (authEmail == null || authEmail.isEmpty) return;
    if (authEmail.toLowerCase() == profile.email.trim().toLowerCase()) return;
    _userRepository.updateFields(uid, {'email': authEmail}).catchError((_) {});
  }

  /// Resolves the signed-in user's profile, or null when signed out.
  Future<UserModel?> loadCurrentProfile() async {
    final user = _authService.firebaseUser;
    if (user == null) return null;
    final profile = await _authService.ensureProfile(user);
    currentUser.value = profile;
    return profile;
  }

  bool get needsEmailVerification => _authService.needsEmailVerification;

  /// Sends a signed-in user on: email verification first (email/password
  /// accounts), then location setup or the main app.
  void routeAfterSignIn(UserModel profile, {bool verificationSent = false}) {
    currentUser.value = profile;
    if (needsEmailVerification) {
      Get.offAllNamed(
        AppRoutes.verifyEmail,
        arguments: {'sent': verificationSent},
      );
      return;
    }
    Get.offAllNamed(
      profile.hasLocation ? AppRoutes.mainNav : AppRoutes.locationSetup,
    );
  }

  /// Completes a verified phone credential for the given [purpose] and
  /// navigates to the next screen. Errors propagate to the caller.
  Future<void> completePhoneVerification({
    required OtpPurpose purpose,
    required PhoneAuthCredential credential,
    required String phone,
  }) async {
    switch (purpose) {
      case OtpPurpose.signIn:
        final profile = await _authService.signInWithPhone(credential);
        routeAfterSignIn(profile);
      case OtpPurpose.addPhone:
        await _authService.linkPhone(credential, phone);
        final current = currentUser.value;
        if (current != null) updateUser(current.copyWith(phone: phone));
        // Back to Edit Profile (an auto-verified code never opens the OTP page).
        if (Get.currentRoute == AppRoutes.otpVerification) Get.back();
        SnackbarService.showSuccess(
          'Phone Verified',
          '$phone can now be used to sign in and reset your password.',
        );
      case OtpPurpose.resetPassword:
        await _authService.verifyPhoneForPasswordReset(credential);
        if (Get.currentRoute == AppRoutes.otpVerification) {
          Get.offNamed(AppRoutes.resetPassword);
        } else {
          Get.toNamed(AppRoutes.resetPassword);
        }
    }
  }

  bool get accountUsesPassword => _authService.accountUsesPassword;

  /// "Google" or "Apple" when deletion is confirmed with that account.
  String? get deletionConfirmationLabel =>
      switch (_authService.deletionConfirmationProvider) {
        'google.com' => 'Google',
        'apple.com' => 'Apple',
        _ => null,
      };

  /// Sends an SMS code to [phone] for the signed-in account.
  Future<SmsVerificationResult> sendPhoneCode(String phone) =>
      _authService.sendPhoneCode(phone);

  /// Deletes the account and all its data. Returns false if the user
  /// cancelled re-authentication; throws when the deletion failed.
  ///
  /// Does not navigate: the caller closes its dialog first, then calls
  /// [finishAccountDeletion].
  Future<bool> deleteAccount({String? password}) async {
    final confirmed = await _authService.reauthenticateForDeletion(
      password: password,
    );
    if (!confirmed) return false;

    await _runBeforeSignOut();
    // Stop listeners so they don't report errors while data is removed.
    await _profileSubscription?.cancel();
    _profileSubscription = null;
    _householdStore.clear();

    try {
      await _authService.deleteAccount();
    } catch (_) {
      // The Firebase user is gone: the deletion itself succeeded (only a
      // later clean-up step failed).
      if (_authService.firebaseUser == null) {
        currentUser.value = null;
        return true;
      }
      _onAuthChanged(_authService.firebaseUser);
      rethrow;
    }

    currentUser.value = null;
    return true;
  }

  /// After a successful deletion: replaces the whole stack with Sign In and
  /// confirms once that screen is showing.
  void finishAccountDeletion() {
    Get.offAllNamed(AppRoutes.signIn);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      SnackbarService.showSuccess(
        'Account Deleted',
        'Your account and data have been permanently deleted.',
      );
    });
  }

  /// Applies a local profile change immediately (Firestore sync follows).
  void updateUser(UserModel user) {
    currentUser.value = user;
  }

  /// True while [signOut] runs; further sign-out requests are ignored.
  final isSigningOut = false.obs;

  /// Signs out behind a "Signing out…" indicator, then replaces the whole
  /// stack with Sign In. The signed-in screens keep their data until they
  /// are gone (no blank screen). On failure the user stays signed in where
  /// they were and sees why.
  Future<void> signOut() async {
    if (isSigningOut.value) return;
    isSigningOut.value = true;
    AppLoadingDialog.show('Signing out…');
    try {
      await _endSession();
    } catch (error) {
      if (_authService.firebaseUser != null) {
        isSigningOut.value = false;
        _onAuthChanged(_authService.firebaseUser);
        AppLoadingDialog.hide();
        SnackbarService.showError(
          'Log Out Failed',
          FirebaseErrorMapper.message(error),
        );
        return;
      }
      // The session ended anyway (only a clean-up step failed).
    }
    // Removes the indicator together with the signed-in screens.
    Get.offAllNamed(AppRoutes.signIn);
    AppLoadingDialog.markClosed();
    _clearLocalData();
    isSigningOut.value = false;
  }

  /// Signs out without navigating (e.g. before switching accounts).
  Future<void> clearSession() async {
    await _endSession();
    _clearLocalData();
  }

  Future<void> _endSession() async {
    await _runBeforeSignOut();
    await _profileSubscription?.cancel();
    _profileSubscription = null;
    await _authService.signOut();
  }

  void _clearLocalData() {
    _householdStore.clear();
    currentUser.value = null;
  }

  @override
  void onClose() {
    _authSubscription?.cancel();
    _profileSubscription?.cancel();
    super.onClose();
  }
}
