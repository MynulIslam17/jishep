import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:gps_cielo/core/config/app_config.dart';
import 'package:gps_cielo/core/utils/firebase_error_mapper.dart';
import 'package:gps_cielo/core/utils/show_snackbar.dart';
import 'package:gps_cielo/core/utils/validators.dart';
import 'package:gps_cielo/features/auth/data/repositories/auth_repository.dart';
import 'package:gps_cielo/features/auth/domain/services/auth_service.dart';
import 'package:gps_cielo/features/auth/presentation/controllers/auth_controller.dart';
import 'package:gps_cielo/routes/app_routes.dart';

class ForgotPasswordController extends GetxController {
  final AuthService _authService;
  final AuthController _globalAuthController;

  ForgotPasswordController(this._authService, this._globalAuthController);

  final phoneController = TextEditingController();
  final emailController = TextEditingController();
  final completePhoneNumber = ''.obs;
  final isLoading = false.obs;

  /// Reset by emailed link instead of an SMS code (the only option while
  /// phone sign-in is off).
  final useEmail = (!AppConfig.phoneAuthEnabled).obs;

  /// Set once the reset email was sent (shows the confirmation).
  final emailSentTo = RxnString();

  void setUseEmail(bool value) {
    useEmail.value = value;
    emailSentTo.value = null;
  }

  /// Emails a password reset link. Firebase does not reveal whether the
  /// address has an account, so the message is the same either way.
  Future<void> sendResetEmail() async {
    if (isLoading.value) return;
    final email = emailController.text.trim();
    final error = AppValidator.email(email);
    if (error != null) {
      SnackbarService.showError('Validation', error);
      return;
    }
    isLoading.value = true;
    try {
      await _authService.sendPasswordResetEmail(email);
      emailSentTo.value = email;
    } catch (error) {
      SnackbarService.showError(
        'Could Not Send',
        FirebaseErrorMapper.message(error),
      );
    } finally {
      isLoading.value = false;
    }
  }

  void updatePhoneNumber(String number) {
    completePhoneNumber.value = number;
  }

  /// Sends an SMS code to the phone number linked to the account.
  Future<void> sendOtp() async {
    if (isLoading.value) return;

    final phone = completePhoneNumber.value.trim();
    if (phone.isEmpty || AppValidator.phone(phoneController.text) != null) {
      SnackbarService.showError(
        'Validation',
        'Please enter a valid phone number',
      );
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
              'purpose': OtpPurpose.resetPassword,
              'verificationId': verificationId,
              'resendToken': resendToken,
            },
          );
        case SmsAutoVerified(:final credential):
          await _globalAuthController.completePhoneVerification(
            purpose: OtpPurpose.resetPassword,
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

  @override
  void onClose() {
    phoneController.dispose();
    emailController.dispose();
    super.onClose();
  }
}
