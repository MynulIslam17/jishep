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
  final isLoading = false.obs;
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

    isLoading.value = true;
    try {
      final profile = await _authService.signInWithEmail(email, password);
      _globalAuthController.routeAfterSignIn(profile);
    } catch (error) {
      SnackbarService.showError(
        'Sign In Failed',
        FirebaseErrorMapper.message(error),
      );
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> _sendPhoneCode() async {
    final phone = completePhoneNumber.value.trim();
    if (phone.isEmpty || AppValidator.phone(phoneController.text) != null) {
      SnackbarService.showError('Validation', 'Please enter a valid phone number');
      return;
    }

    isLoading.value = true;
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
      isLoading.value = false;
    }
  }

  Future<void> signInWithGoogle() async {
    if (isLoading.value) return;
    isLoading.value = true;
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
      isLoading.value = false;
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
