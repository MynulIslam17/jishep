import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:gps_cielo/core/utils/firebase_error_mapper.dart';
import 'package:gps_cielo/core/utils/show_snackbar.dart';
import 'package:gps_cielo/features/auth/data/repositories/auth_repository.dart';
import 'package:gps_cielo/features/auth/domain/services/auth_service.dart';
import 'package:gps_cielo/features/auth/presentation/controllers/auth_controller.dart';

class OtpVerificationController extends GetxController {
  final AuthService _authService;
  final AuthController _globalAuthController;

  OtpVerificationController(this._authService, this._globalAuthController);

  /// Firebase SMS codes are 6 digits.
  static const int codeLength = 6;

  final List<TextEditingController> digitControllers =
      List.generate(codeLength, (_) => TextEditingController());
  final List<FocusNode> digitFocusNodes =
      List.generate(codeLength, (_) => FocusNode());

  final phoneRx = ''.obs;
  String get phone => phoneRx.value;

  final isLoading = false.obs;
  final countdown = 45.obs;
  Timer? _timer;

  OtpPurpose _purpose = OtpPurpose.signIn;
  String _verificationId = '';
  int? _resendToken;
  StreamSubscription<PhoneAuthCredential>? _autoVerifySubscription;

  @override
  void onInit() {
    super.onInit();
    final args = Get.arguments as Map<String, dynamic>?;
    phoneRx.value = args?['phone'] as String? ?? '';
    _purpose = args?['purpose'] as OtpPurpose? ?? OtpPurpose.signIn;
    _verificationId = args?['verificationId'] as String? ?? '';
    _resendToken = args?['resendToken'] as int?;

    _autoVerifySubscription =
        _authService.autoVerifiedCredentials.listen(_complete);
    startCountdown();
  }

  void startCountdown() {
    countdown.value = 45;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (countdown.value > 0) {
        countdown.value--;
      } else {
        timer.cancel();
      }
    });
  }

  Future<void> resendCode() async {
    if (countdown.value > 0 || phone.isEmpty) return;
    startCountdown();

    try {
      final result = await _authService.sendPhoneCode(
        phone,
        resendToken: _resendToken,
      );
      switch (result) {
        case SmsCodeSent(:final verificationId, :final resendToken):
          _verificationId = verificationId;
          _resendToken = resendToken;
          SnackbarService.showSuccess(
            'Code Resent',
            'A new verification code has been sent to $phone',
          );
        case SmsAutoVerified(:final credential):
          await _complete(credential);
      }
    } catch (error) {
      SnackbarService.showError(
        'Resend Failed',
        FirebaseErrorMapper.message(error),
      );
    }
  }

  Future<void> verifyCode() async {
    final otp = digitControllers.map((c) => c.text.trim()).join();
    if (otp.length < codeLength) {
      SnackbarService.showError(
        'Incomplete Code',
        'Please enter all $codeLength digits',
      );
      return;
    }
    if (_verificationId.isEmpty) {
      SnackbarService.showError(
        'Verification Failed',
        'Please request a new code.',
      );
      return;
    }

    await _complete(
      _authService.credentialFromCode(
        verificationId: _verificationId,
        smsCode: otp,
      ),
    );
  }

  Future<void> _complete(PhoneAuthCredential credential) async {
    if (isLoading.value) return;
    isLoading.value = true;
    try {
      await _globalAuthController.completePhoneVerification(
        purpose: _purpose,
        credential: credential,
        phone: phone,
      );
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
    _timer?.cancel();
    _autoVerifySubscription?.cancel();
    for (final c in digitControllers) {
      c.dispose();
    }
    for (final f in digitFocusNodes) {
      f.dispose();
    }
    super.onClose();
  }
}
