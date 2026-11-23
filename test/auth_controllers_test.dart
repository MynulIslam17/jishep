import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:gps_cielo/features/auth/domain/services/auth_service.dart';
import 'package:gps_cielo/features/auth/presentation/controllers/auth_controller.dart';
import 'package:gps_cielo/features/auth/presentation/controllers/forgot_password_controller.dart';
import 'package:gps_cielo/features/auth/presentation/controllers/sign_up_controller.dart';

class _FakeAuthService implements AuthService {
  final resetEmails = <String>[];

  @override
  Future<void> sendPasswordResetEmail(String email) async =>
      resetEmails.add(email);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeAuthController extends GetxController implements AuthController {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUp(() => Get.testMode = true);

  test('the Terms checkbox starts unticked', () {
    final controller = SignUpController(
      _FakeAuthService(),
      _FakeAuthController(),
    );
    expect(controller.agreeToTerms.value, isFalse);
  });

  group('Forgot password by email', () {
    test('sends the reset link and shows where it went', () async {
      final service = _FakeAuthService();
      final controller = ForgotPasswordController(
        service,
        _FakeAuthController(),
      );
      controller.setUseEmail(true);
      controller.emailController.text = '  a@example.com ';

      await controller.sendResetEmail();

      expect(service.resetEmails, ['a@example.com']);
      expect(controller.emailSentTo.value, 'a@example.com');
      expect(controller.isLoading.value, isFalse);
    });

    test('resets by email while phone sign-in is off', () {
      final controller = ForgotPasswordController(
        _FakeAuthService(),
        _FakeAuthController(),
      );
      expect(controller.useEmail.value, isTrue);
    });

    test('switching method clears the confirmation', () async {
      final controller = ForgotPasswordController(
        _FakeAuthService(),
        _FakeAuthController(),
      );
      controller.setUseEmail(true);
      controller.emailController.text = 'a@example.com';
      await controller.sendResetEmail();
      controller.setUseEmail(false);
      expect(controller.emailSentTo.value, isNull);
      expect(controller.useEmail.value, isFalse);
    });
  });
}
