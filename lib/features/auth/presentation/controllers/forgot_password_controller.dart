import 'package:flutter/material.dart';
import 'package:get/get.dart';
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
  final completePhoneNumber = ''.obs;
  final isLoading = false.obs;

  void updatePhoneNumber(String number) {
    completePhoneNumber.value = number;
  }

  /// Sends an SMS code to the phone number linked to the account.
  Future<void> sendOtp() async {
    if (isLoading.value) return;

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
    super.onClose();
  }
}
