import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:gps_cielo/core/models/user_model.dart';
import 'package:gps_cielo/features/auth/domain/services/auth_service.dart';
import 'package:gps_cielo/features/auth/presentation/controllers/auth_controller.dart';
import 'package:gps_cielo/features/auth/presentation/controllers/sign_up_controller.dart';
import 'package:gps_cielo/features/auth/presentation/controllers/verify_email_controller.dart';

class _User implements User {
  @override
  String? get email => 'new@example.com';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Service implements AuthService {
  bool verified = false;
  int checks = 0;
  int sends = 0;
  Object? sendError;
  final registered = <String>[];

  @override
  User? get firebaseUser => _User();

  @override
  Future<bool> checkEmailVerified() async {
    checks++;
    return verified;
  }

  @override
  Future<void> sendEmailVerification() async {
    if (sendError != null) throw sendError!;
    sends++;
  }

  @override
  Future<UserModel> register({
    required String fullName,
    required String email,
    required String password,
  }) async {
    registered.add(email);
    return UserModel(id: 'u1', fullName: fullName, email: email);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Auth extends GetxController implements AuthController {
  final routed = <bool>[];
  int signOuts = 0;

  @override
  Future<UserModel?> loadCurrentProfile() async =>
      UserModel(id: 'u1', fullName: 'N', email: 'new@example.com');

  @override
  void routeAfterSignIn(UserModel profile, {bool verificationSent = false}) =>
      routed.add(verificationSent);

  @override
  Future<void> signOut() async => signOuts++;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => Get.testMode = true);

  group('Sign up form', () {
    SignUpController form(_Service s, _Auth a) {
      final c = SignUpController(s, a)
        ..nameController.text = 'New Person'
        ..emailController.text = 'new@example.com'
        ..passwordController.text = 'password1'
        ..confirmPasswordController.text = 'password1';
      return c;
    }

    test('passwords must match', () {
      final c = form(_Service(), _Auth())
        ..confirmPasswordController.text = 'password2';
      expect(c.validate(), 'Passwords do not match');
    });

    test('creates the account, sends the link, opens Verify Email', () async {
      final s = _Service();
      final a = _Auth();
      final c = form(s, a)..agreeToTerms.value = true;
      await c.signUp();
      expect(s.registered, ['new@example.com']);
      expect(s.sends, 1);
      expect(a.routed, [true]);
    });

    test('a failed send still opens Verify Email (to resend)', () async {
      final s = _Service()..sendError = Exception('quota');
      final a = _Auth();
      final c = form(s, a)..agreeToTerms.value = true;
      await c.signUp();
      expect(a.routed, [false]);
    });

    test('nothing happens without accepting the terms', () async {
      final s = _Service();
      await form(s, _Auth()).signUp();
      expect(s.registered, isEmpty);
    });
  });

  group('Verify Email page', () {
    test('a tap that finds it not verified stays on the page', () async {
      final s = _Service();
      final a = _Auth();
      final c = VerifyEmailController(s, a)..onInit();
      await c.check();
      expect(a.routed, isEmpty);
      expect(c.isVerified.value, isFalse);
      expect(c.isChecking.value, isFalse);
      c.onClose();
    });

    test('verified: shows Verified, then continues into the app', () async {
      final s = _Service()..verified = true;
      final a = _Auth();
      final c = VerifyEmailController(s, a)..onInit();
      final done = c.check();
      await Future<void>.delayed(Duration.zero);
      expect(c.isVerified.value, isTrue);
      await done;
      expect(a.routed, hasLength(1));
      c.onClose();
    });

    VerifyEmailController fast(_Service s, _Auth a, {Duration? max}) =>
        VerifyEmailController(
          s,
          a,
          fastInterval: const Duration(milliseconds: 20),
          slowInterval: const Duration(milliseconds: 40),
          fastPhase: const Duration(milliseconds: 60),
          maxAutoCheck: max ?? const Duration(minutes: 1),
        )..onInit();

    test('background checks never show the button loader', () async {
      final s = _Service();
      final c = fast(s, _Auth());
      final seen = <bool>[];
      final sub = c.isChecking.listen(seen.add);
      await Future<void>.delayed(const Duration(milliseconds: 90));
      expect(s.checks, greaterThanOrEqualTo(2));
      expect(seen, isNot(contains(true)));
      expect(c.isAutoChecking.value, isTrue);
      await sub.cancel();
      c.onClose();
    });

    test('continues automatically once the link is clicked', () async {
      final s = _Service();
      final a = _Auth();
      final c = fast(s, a);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(a.routed, isEmpty);

      s.verified = true;
      await Future<void>.delayed(const Duration(milliseconds: 900));
      expect(a.routed, hasLength(1));
      final checks = s.checks;
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(s.checks, checks, reason: 'checks stop once verified');
      c.onClose();
    });

    test('auto-checks stop after the limit; the button still works', () async {
      final s = _Service();
      final a = _Auth();
      final c = fast(s, a, max: const Duration(milliseconds: 60));
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(c.isAutoChecking.value, isFalse);
      final checks = s.checks;
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(s.checks, checks);

      s.verified = true;
      await c.check();
      expect(a.routed, hasLength(1));
      c.onClose();
    });

    test('no checks while the app is in the background', () async {
      final s = _Service();
      final c = fast(s, _Auth());
      c.didChangeAppLifecycleState(AppLifecycleState.paused);
      final checks = s.checks;
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(s.checks, checks);

      // Back from the mail app: checks immediately.
      c.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await Future<void>.delayed(Duration.zero);
      expect(s.checks, checks + 1);
      c.onClose();
    });

    test('resend sends a new link, then waits for the cooldown', () async {
      final s = _Service();
      final c = VerifyEmailController(s, _Auth())..onInit();
      expect(c.cooldown.value, 0);
      await c.resend();
      expect(s.sends, 1);
      expect(c.cooldown.value, VerifyEmailController.resendCooldown);
      await c.resend();
      expect(s.sends, 1);
      c.onClose();
    });

    test('sign out leaves the page', () async {
      final a = _Auth();
      final c = VerifyEmailController(_Service(), a)..onInit();
      await c.signOut();
      expect(a.signOuts, 1);
      c.onClose();
    });
  });
}
