import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:gps_cielo/core/utils/firebase_error_mapper.dart';
import 'package:gps_cielo/core/utils/show_snackbar.dart';
import 'package:gps_cielo/core/utils/validators.dart';
import 'package:gps_cielo/features/auth/domain/services/auth_service.dart';
import 'package:gps_cielo/features/auth/presentation/controllers/auth_controller.dart';

class SignUpController extends GetxController {
  final AuthService _authService;
  final AuthController _globalAuthController;

  SignUpController(this._authService, this._globalAuthController);

  // Form Controllers
  final nameController = TextEditingController();
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final confirmPasswordController = TextEditingController();

  // Reactive State
  final isLoading = false.obs;
  final isPasswordVisible = false.obs;

  /// The user must tick this themselves.
  final agreeToTerms = false.obs;

  void togglePasswordVisibility() {
    isPasswordVisible.value = !isPasswordVisible.value;
  }

  /// First problem with the form, or null when it can be submitted.
  String? validate() {
    final password = passwordController.text;
    return AppValidator.name(nameController.text.trim()) ??
        AppValidator.email(emailController.text.trim()) ??
        AppValidator.password(password, minLength: 8) ??
        AppValidator.confirmPassword(confirmPasswordController.text, password);
  }

  /// Creates the account, emails a verification link, then waits on the
  /// Verify Email screen until the link is clicked.
  Future<void> signUp() async {
    if (isLoading.value) return;

    final validationError = validate();
    if (validationError != null) {
      SnackbarService.showError('Validation', validationError);
      return;
    }
    if (!agreeToTerms.value) {
      SnackbarService.showError(
        'Terms',
        'Please accept the Terms of Use and Privacy Policy',
      );
      return;
    }

    isLoading.value = true;
    try {
      final profile = await _authService.register(
        fullName: nameController.text.trim(),
        email: emailController.text.trim(),
        password: passwordController.text,
      );

      var sent = true;
      try {
        await _authService.sendEmailVerification();
      } catch (_) {
        // The account exists; the Verify Email screen offers a resend.
        sent = false;
      }
      _globalAuthController.routeAfterSignIn(profile, verificationSent: sent);
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
    passwordController.dispose();
    confirmPasswordController.dispose();
    super.onClose();
  }
}
