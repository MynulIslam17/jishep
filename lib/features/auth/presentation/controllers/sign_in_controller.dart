import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:gps_cielo/core/utils/firebase_error_mapper.dart';
import 'package:gps_cielo/core/utils/show_snackbar.dart';
import 'package:gps_cielo/core/utils/validators.dart';
import 'package:gps_cielo/features/auth/data/repositories/auth_repository.dart';
import 'package:gps_cielo/features/auth/domain/services/auth_service.dart';
import 'package:gps_cielo/features/auth/presentation/controllers/auth_controller.dart';
import 'package:gps_cielo/routes/app_routes.dart';

class SignInController extends GetxController {
  final AuthService _authService;
  final AuthController _globalAuthController;

  SignInController(this._authService, this._globalAuthController);

  // Form Controllers
  final emailController = TextEditingController();
  final phoneController = TextEditingController();
  final passwordController = TextEditingController();

  // Reactive State
  /// True while any sign-in is running (blocks repeated taps on every
  /// sign-in button).
  final isLoading = false.obs;

  /// Which sign-in is running, so only its own button shows a spinner.
  final busyWith = Rxn<SignInMethod>();
  final isPasswordVisible = false.obs;
  final isPhoneLogin = false.obs;
  final completePhoneNumber = ''.obs;

  void togglePasswordVisibility() {
    isPasswordVisible.value = !isPasswordVisible.value;
  }

  void setLoginMode(bool usePhone) {
    isPhoneLogin.value = usePhone;
  }

  void updatePhoneNumber(String fullNumber) {
    completePhoneNumber.value = fullNumber;
  }

  Future<void> signIn() async {
    if (isLoading.value) return;
    if (isPhoneLogin.value) {
      await _sendPhoneCode();
    } else {
      await _signInWithEmail();
    }
  }

  Future<void> _signInWithEmail() async {
    final email = emailController.text.trim();
    final password = passwordController.text;

    final emailError = AppValidator.email(email);
    if (emailError != null || password.isEmpty) {
      SnackbarService.showError(
        'Validation',
        emailError ?? 'Please enter your password',
      );
      return;
    }

    _setBusy(SignInMethod.form);
    try {
      final profile = await _authService.signInWithEmail(email, password);
      _globalAuthController.routeAfterSignIn(profile);
    } catch (error) {
      SnackbarService.showError(
        'Sign In Failed',
        FirebaseErrorMapper.message(error),
      );
    } finally {
      _setBusy(null);
    }
  }

  Future<void> _sendPhoneCode() async {
    final phone = completePhoneNumber.value.trim();
    if (phone.isEmpty || AppValidator.phone(phoneController.text) != null) {
      SnackbarService.showError(
        'Validation',
        'Please enter a valid phone number',
      );
      return;
    }

    _setBusy(SignInMethod.form);
    try {
      final result = await _authService.sendPhoneCode(phone);
      switch (result) {
        case SmsCodeSent(:final verificationId, :final resendToken):
          Get.toNamed(
            AppRoutes.otpVerification,
            arguments: {
              'phone': phone,
              'purpose': OtpPurpose.signIn,
              'verificationId': verificationId,
              'resendToken': resendToken,
            },
          );
        case SmsAutoVerified(:final credential):
          await _globalAuthController.completePhoneVerification(
            purpose: OtpPurpose.signIn,
            credential: credential,
            phone: phone,
          );
      }
    } catch (error) {
      SnackbarService.showError(
        'Verification Failed',
        FirebaseErrorMapper.message(error),
      );
    } finally {
      _setBusy(null);
    }
  }

  void _setBusy(SignInMethod? method) {
    busyWith.value = method;
    isLoading.value = method != null;
  }

  /// Sign in with Apple is offered on iOS only.
  bool get showAppleSignIn => _authService.appleSignInAvailable;

  /// Native Sign in with Apple. Closing the Apple sheet is not an error.
  Future<void> signInWithApple() async {
    if (isLoading.value) return;
    _setBusy(SignInMethod.apple);
    try {
      final profile = await _authService.signInWithApple();
      if (profile != null) {
        _globalAuthController.routeAfterSignIn(profile);
      }
    } catch (error) {
      SnackbarService.showError(
        'Apple Sign-In Failed',
        FirebaseErrorMapper.message(error),
      );
    } finally {
      _setBusy(null);
    }
  }

  Future<void> signInWithGoogle() async {
    if (isLoading.value) return;
    _setBusy(SignInMethod.google);
    try {
      final profile = await _authService.signInWithGoogle();
      if (profile != null) {
        _globalAuthController.routeAfterSignIn(profile);
      }
    } catch (error) {
      SnackbarService.showError(
        'Google Sign-In Failed',
        FirebaseErrorMapper.message(error),
      );
    } finally {
      _setBusy(null);
    }
  }

  @override
  void onClose() {
    emailController.dispose();
    phoneController.dispose();
    passwordController.dispose();
    super.onClose();
  }
}

/// The sign-in methods on the Sign In screen.
enum SignInMethod { form, apple, google }
