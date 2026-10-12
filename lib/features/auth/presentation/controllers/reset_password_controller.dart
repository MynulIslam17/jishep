import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:gps_cielo/core/utils/firebase_error_mapper.dart';
import 'package:gps_cielo/core/utils/show_snackbar.dart';
import 'package:gps_cielo/features/auth/domain/services/auth_service.dart';

/// Sets a new password for the account that was just verified by SMS.
class ResetPasswordController extends GetxController {
  final AuthService _authService;

  ResetPasswordController(this._authService);

  final passwordController = TextEditingController();
  final confirmPasswordController = TextEditingController();
  final formKey = GlobalKey<FormState>();

  final isPasswordVisible = false.obs;
  final isConfirmPasswordVisible = false.obs;
  final isLoading = false.obs;

  bool _completed = false;

  void togglePasswordVisibility() {
    isPasswordVisible.value = !isPasswordVisible.value;
  }

  void toggleConfirmPasswordVisibility() {
    isConfirmPasswordVisible.value = !isConfirmPasswordVisible.value;
  }

  Future<bool> resetPassword() async {
    if (!(formKey.currentState?.validate() ?? false)) {
      return false;
    }

    final password = passwordController.text;
    final confirm = confirmPasswordController.text;

    if (password != confirm) {
      SnackbarService.showError('Mismatch', 'Passwords do not match');
      return false;
    }

    isLoading.value = true;
    try {
      await _authService.resetPassword(password);
      _completed = true;
      return true;
    } catch (error) {
      SnackbarService.showError(
        'Reset Failed',
        FirebaseErrorMapper.message(error),
      );
      return false;
    } finally {
      isLoading.value = false;
    }
  }

  @override
  void onClose() {
    // The SMS step signed the user in; do not leave that session behind if
    // they back out without choosing a new password.
    if (!_completed && _authService.firebaseUser != null) {
      _authService.signOut();
    }
    passwordController.dispose();
    confirmPasswordController.dispose();
    super.onClose();
  }
}
