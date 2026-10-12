import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:gps_cielo/core/utils/firebase_error_mapper.dart';
import 'package:gps_cielo/core/utils/show_snackbar.dart';
import 'package:gps_cielo/core/utils/validators.dart';
import 'package:gps_cielo/features/auth/data/repositories/auth_repository.dart';
import 'package:gps_cielo/features/auth/domain/services/auth_service.dart';
import 'package:gps_cielo/features/auth/presentation/controllers/auth_controller.dart';
import 'package:gps_cielo/routes/app_routes.dart';

class SignUpController extends GetxController {
  final AuthService _authService;
  final AuthController _globalAuthController;

  SignUpController(this._authService, this._globalAuthController);

  // Form Controllers
  final nameController = TextEditingController();
  final emailController = TextEditingController();
  final phoneController = TextEditingController();
  final passwordController = TextEditingController();

  // Reactive State
  final isLoading = false.obs;
  final isPasswordVisible = false.obs;
  final agreeToTerms = true.obs;
  final completePhoneNumber = ''.obs;

  void togglePasswordVisibility() {
    isPasswordVisible.value = !isPasswordVisible.value;
  }

  void updatePhoneNumber(String number) {
    completePhoneNumber.value = number;
  }

  /// Creates the account, then verifies the phone number by SMS so it can be
  /// used for phone sign-in and password recovery.
  Future<void> signUp() async {
    if (isLoading.value) return;

    final name = nameController.text.trim();
    final email = emailController.text.trim();
    final password = passwordController.text;
    final phone = completePhoneNumber.value.trim();

    final validationError = AppValidator.name(name) ??
        AppValidator.email(email) ??
        AppValidator.phone(phoneController.text) ??
        AppValidator.password(password, minLength: 8);
    if (validationError != null || phone.isEmpty) {
      SnackbarService.showError(
        'Validation',
        validationError ?? 'Phone number is required',
      );
      return;
    }

    if (!agreeToTerms.value) {
      SnackbarService.showError('Terms', 'Please accept the Terms of Use');
      return;
    }

    isLoading.value = true;
    try {
      final profile = await _authService.register(
        fullName: name,
        email: email,
        password: password,
        phone: phone,
      );
      _globalAuthController.updateUser(profile);

      final result = await _authService.sendPhoneCode(phone);
      switch (result) {
        case SmsCodeSent(:final verificationId, :final resendToken):
          Get.toNamed(
            AppRoutes.otpVerification,
            arguments: {
              'phone': phone,
              'purpose': OtpPurpose.linkPhone,
              'verificationId': verificationId,
              'resendToken': resendToken,
            },
          );
        case SmsAutoVerified(:final credential):
          await _globalAuthController.completePhoneVerification(
            purpose: OtpPurpose.linkPhone,
            credential: credential,
            phone: phone,
          );
      }
    } catch (error) {
      SnackbarService.showError(
        'Sign Up Failed',
        FirebaseErrorMapper.message(error),
      );
    } finally {
      isLoading.value = false;
    }
  }

  @override
  void onClose() {
    nameController.dispose();
    emailController.dispose();
    phoneController.dispose();
    passwordController.dispose();
    super.onClose();
  }
}
