import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:gps_cielo/core/models/user_model.dart';
import 'package:gps_cielo/features/auth/domain/services/auth_service.dart';
import 'package:gps_cielo/features/auth/presentation/controllers/auth_controller.dart';
import 'package:gps_cielo/features/auth/presentation/controllers/sign_in_controller.dart';
import 'package:gps_cielo/features/auth/presentation/pages/sign_in_screen.dart';

class _Service implements AuthService {
  _Service(this.available);

  final bool available;
  UserModel? appleProfile;
  Completer<UserModel?>? pending;
  int appleCalls = 0;

  @override
  bool get appleSignInAvailable => available;

  @override
  Future<UserModel?> signInWithApple() async {
    appleCalls++;
    if (pending != null) return pending!.future;
    return appleProfile;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Auth extends GetxController implements AuthController {
  final routed = <UserModel>[];

  @override
  void routeAfterSignIn(UserModel profile, {bool verificationSent = false}) =>
      routed.add(profile);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUp(() => Get.testMode = true);
  tearDown(Get.reset);

  Future<(_Service, _Auth)> pump(
    WidgetTester tester, {
    required bool ios,
  }) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    final service = _Service(ios);
    final auth = _Auth();
    Get.put(SignInController(service, auth));
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (_, _) => const GetMaterialApp(home: SignInScreen()),
      ),
    );
    await tester.pump();
    return (service, auth);
  }

  testWidgets('iOS shows Continue with Apple next to Google', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    await pump(tester, ios: true);
    expect(find.byKey(const ValueKey('apple-sign-in')), findsOneWidget);
    expect(find.text('Continue with Apple'), findsOneWidget);
    expect(find.text('Continue with Google'), findsOneWidget);
    expect(tester.takeException(), isNull);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('Android does not show the Apple button', (tester) async {
    await pump(tester, ios: false);
    expect(find.byKey(const ValueKey('apple-sign-in')), findsNothing);
    expect(find.text('Continue with Google'), findsOneWidget);
  });

  testWidgets('closing the Apple sheet stays on Sign In without an error', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final (service, auth) = await pump(tester, ios: true);
    await tester.ensureVisible(find.byKey(const ValueKey('apple-sign-in')));
    await tester.tap(find.byKey(const ValueKey('apple-sign-in')));
    await tester.pump();
    expect(service.appleCalls, 1);
    expect(auth.routed, isEmpty);
    expect(find.text('Apple Sign-In Failed'), findsNothing);
    expect(Get.find<SignInController>().isLoading.value, isFalse);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('a successful Apple sign-in uses the normal routing', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final (service, auth) = await pump(tester, ios: true);
    service.appleProfile = UserModel(id: 'apple-1', fullName: '', email: '');
    await tester.ensureVisible(find.byKey(const ValueKey('apple-sign-in')));
    await tester.tap(find.byKey(const ValueKey('apple-sign-in')));
    await tester.pump();
    expect(auth.routed.single.id, 'apple-1');
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets(
    'while the Apple sheet is open only Apple is busy and taps are ignored',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final (service, auth) = await pump(tester, ios: true);
      service.pending = Completer<UserModel?>();
      final apple = find.byKey(const ValueKey('apple-sign-in'));
      await tester.ensureVisible(apple);
      await tester.tap(apple);
      await tester.pump();

      // The email Sign In button does not show a spinner for Apple.
      expect(find.byType(CircularProgressIndicator), findsNothing);
      final c = Get.find<SignInController>();
      expect(c.busyWith.value, SignInMethod.apple);

      await tester.tap(apple, warnIfMissed: false);
      await tester.tap(find.text('Continue with Google'), warnIfMissed: false);
      await tester.pump();
      expect(service.appleCalls, 1);

      service.pending!.complete(null); // user closed the sheet
      await tester.pump();
      expect(c.isLoading.value, isFalse);
      expect(c.busyWith.value, isNull);
      expect(auth.routed, isEmpty);
      debugDefaultTargetPlatformOverride = null;
    },
  );
}
