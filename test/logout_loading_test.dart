import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:gps_cielo/core/data/user_repository.dart';
import 'package:gps_cielo/core/models/user_model.dart';
import 'package:gps_cielo/core/services/household_store.dart';
import 'package:gps_cielo/features/auth/domain/services/auth_service.dart';
import 'package:gps_cielo/features/auth/presentation/controllers/auth_controller.dart';
import 'package:gps_cielo/routes/app_routes.dart';
import 'package:gps_cielo/shared/widgets/dialogs/app_loading_dialog.dart';

class _User implements User {
  @override
  String get uid => 'u1';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Sign-out waits for [gate] (a slow network) and can fail.
class _Service implements AuthService {
  final auth = StreamController<User?>.broadcast();
  User? user = _User();
  Completer<void>? gate;
  Object? error;
  int signOuts = 0;

  @override
  User? get firebaseUser => user;

  @override
  Stream<User?> authStateChanges() => auth.stream;

  @override
  Future<void> signOut() async {
    signOuts++;
    if (gate != null) await gate!.future;
    if (error != null) throw error!;
    user = null;
    auth.add(null);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Users implements UserRepository {
  @override
  // Like Firestore: stays open until cancelled. (onCancel returns a future
  // of the test zone; the default one belongs to the root zone, which
  // fake-async tests never run.)
  Stream<UserModel?> watchUser(String uid) =>
      StreamController<UserModel?>(onCancel: () async {}).stream;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Store extends GetxService implements HouseholdStore {
  int clears = 0;

  @override
  void clear() => clears++;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late _Service service;
  late _Store store;
  late AuthController auth;
  late List<String> hookUids;

  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (_, _) => GetMaterialApp(
          initialRoute: '/profile',
          getPages: [
            GetPage(
              name: '/profile',
              page: () => Scaffold(
                body: Obx(
                  () => Text('Hello ${auth.currentUser.value?.fullName}'),
                ),
              ),
            ),
            GetPage(
              name: AppRoutes.signIn,
              page: () => const Scaffold(body: Text('Sign In screen')),
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  setUp(() {
    Get.testMode = true;
    service = _Service();
    store = _Store();
    auth = AuthController(service, _Users(), store)..onInit();
    auth.currentUser.value = UserModel(
      id: 'u1',
      fullName: 'Maria',
      email: 'maria@example.com',
    );
    hookUids = [];
    auth.addBeforeSignOut((uid) async => hookUids.add(uid));
  });

  tearDown(() async {
    auth.onClose();
    AppLoadingDialog.markClosed();
    await Get.deleteAll(force: true);
    Get.reset();
  });

  testWidgets('shows the iOS indicator at once, ignores repeated taps, '
      'then lands on Sign In', (tester) async {
    await pumpApp(tester);
    service.gate = Completer<void>();

    unawaited(auth.signOut());
    unawaited(auth.signOut()); // a second tap
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Signing out…'), findsOneWidget);
    expect(find.byType(CupertinoActivityIndicator), findsOneWidget);
    expect(auth.isSigningOut.value, isTrue);
    // No blank screen: the signed-in page keeps its data underneath.
    expect(find.text('Hello Maria'), findsOneWidget);

    service.gate!.complete();
    await tester.pumpAndSettle();

    expect(service.signOuts, 1);
    expect(hookUids, ['u1']);
    expect(Get.currentRoute, AppRoutes.signIn);
    expect(find.text('Sign In screen'), findsOneWidget);
    expect(find.text('Signing out…'), findsNothing);
    expect(find.text('Hello Maria'), findsNothing);
    expect(auth.currentUser.value, isNull);
    expect(store.clears, greaterThanOrEqualTo(1));
    expect(auth.isSigningOut.value, isFalse);
    expect(AppLoadingDialog.isOpen, isFalse);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets('Android shows the Material indicator', (tester) async {
    await pumpApp(tester);
    service.gate = Completer<void>();

    unawaited(auth.signOut());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byType(CupertinoActivityIndicator), findsNothing);

    service.gate!.complete();
    await tester.pumpAndSettle();
    expect(Get.currentRoute, AppRoutes.signIn);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets('a failed sign-out closes the indicator, keeps the user signed '
      'in and allows another try', (tester) async {
    await pumpApp(tester);
    service.error = FirebaseAuthException(
      code: 'network-request-failed',
      message: 'offline',
    );

    await auth.signOut();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Signing out…'), findsNothing);
    // (The 'Log Out Failed' snackbar is skipped in Get.testMode.)
    expect(Get.currentRoute, '/profile');
    expect(auth.currentUser.value?.fullName, 'Maria');
    expect(auth.isSigningOut.value, isFalse);
    expect(AppLoadingDialog.isOpen, isFalse);

    // Retry succeeds.
    service.error = null;
    await tester.pump(const Duration(seconds: 4));
    unawaited(auth.signOut());
    await tester.pumpAndSettle();
    expect(service.signOuts, 2);
    expect(Get.currentRoute, AppRoutes.signIn);
  });

  testWidgets('signing in again after logout shows the indicator again', (
    tester,
  ) async {
    await pumpApp(tester);
    unawaited(auth.signOut());
    await tester.pumpAndSettle();
    expect(Get.currentRoute, AppRoutes.signIn);

    // Signed in again, then logs out a second time.
    service.user = _User();
    Get.offAllNamed('/profile');
    await tester.pumpAndSettle();
    service.gate = Completer<void>();
    unawaited(auth.signOut());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Signing out…'), findsOneWidget);
    service.gate!.complete();
    await tester.pumpAndSettle();
    expect(Get.currentRoute, AppRoutes.signIn);
    expect(service.signOuts, 2);
  });
}
