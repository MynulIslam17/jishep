import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:get/get.dart';
import 'package:gps_cielo/core/data/user_repository.dart';
import 'package:gps_cielo/core/models/user_model.dart';
import 'package:gps_cielo/core/services/household_store.dart';
import 'package:gps_cielo/features/auth/domain/services/auth_service.dart';
import 'package:gps_cielo/routes/app_routes.dart';

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
      currentUser.value = null;
      _householdStore.clear();
      return;
    }

    _profileSubscription = _userRepository.watchUser(user.uid).listen(
      (profile) {
        if (profile == null) return;
        currentUser.value = profile;
        _householdStore.bindUser(profile);
      },
      onError: (_) {},
    );
  }

  /// Resolves the signed-in user's profile, or null when signed out.
  Future<UserModel?> loadCurrentProfile() async {
    final user = _authService.firebaseUser;
    if (user == null) return null;
    final profile = await _authService.ensureProfile(user);
    currentUser.value = profile;
    return profile;
  }

  /// Sends a freshly signed-in user to location setup or the main app.
  void routeAfterSignIn(UserModel profile) {
    currentUser.value = profile;
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
      case OtpPurpose.linkPhone:
        await _authService.linkPhone(credential, phone);
        Get.offAllNamed(AppRoutes.locationSetup);
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

  /// Deletes the account and all its data, then returns to Sign In.
  /// Returns false if the user cancelled re-authentication.
  Future<bool> deleteAccount({String? password}) async {
    final confirmed =
        await _authService.reauthenticateForDeletion(password: password);
    if (!confirmed) return false;

    // Stop listeners so they don't report errors while data is removed.
    await _profileSubscription?.cancel();
    _profileSubscription = null;
    _householdStore.clear();

    try {
      await _authService.deleteAccount();
    } catch (_) {
      _onAuthChanged(_authService.firebaseUser);
      rethrow;
    }

    currentUser.value = null;
    Get.offAllNamed(AppRoutes.signIn);
    return true;
  }

  /// Applies a local profile change immediately (Firestore sync follows).
  void updateUser(UserModel user) {
    currentUser.value = user;
  }

  /// Signs out and returns to the Sign In screen.
  Future<void> signOut() async {
    await clearSession();
    Get.offAllNamed(AppRoutes.signIn);
  }

  Future<void> clearSession() async {
    await _profileSubscription?.cancel();
    _profileSubscription = null;
    _householdStore.clear();
    currentUser.value = null;
    await _authService.signOut();
  }

  @override
  void onClose() {
    _authSubscription?.cancel();
    _profileSubscription?.cancel();
    super.onClose();
  }
}
