import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:gps_cielo/core/models/household_model.dart';
import 'package:gps_cielo/core/models/user_model.dart';
import 'package:gps_cielo/features/auth/presentation/controllers/auth_controller.dart';
import 'package:gps_cielo/features/home/domain/services/home_service.dart';
import 'package:gps_cielo/features/home/presentation/controllers/home_controller.dart';
import 'package:gps_cielo/features/home/presentation/pages/home_screen.dart';

class _Auth extends GetxController implements AuthController {
  _Auth(UserModel? user) {
    currentUser.value = user;
  }

  @override
  final currentUser = Rxn<UserModel>();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Home implements HomeService {
  @override
  final neighborhood = <HouseholdModel>[].obs;
  @override
  final isLoading = false.obs;
  @override
  final homeUnavailable = false.obs;
  final prayed = <String>[];

  @override
  Stream<int> watchUnreadNotificationCount() => Stream.value(2);

  @override
  Future<void> togglePray(String householdId) async => prayed.add(householdId);

  @override
  Future<void> refreshNeighborhood() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

HouseholdModel home(int n, {DateTime? prayedAt}) => HouseholdModel(
  id: 'h$n',
  number: n,
  residentName: n == 1 ? 'The Lopez Family' : '',
  address: '$n MARKET ST',
  latitude: 40.9168 + n * 0.0001,
  longitude: -74.1718,
  isPrayed: prayedAt != null,
  prayedAt: prayedAt,
);

UserModel user({bool located = true}) => UserModel(
  id: 'u1',
  fullName: 'Maria Lopez',
  email: 'm@example.com',
  address: '151 Market St, Paterson, NJ',
  latitude: located ? 40.9168 : null,
  longitude: located ? -74.1718 : null,
);

void main() {
  late _Home service;

  Future<void> pump(WidgetTester tester, {UserModel? profile}) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.7;
    addTearDown(tester.view.reset);
    Get.testMode = true;
    Get.put<HomeController>(HomeController(service, _Auth(profile ?? user())));
    addTearDown(Get.reset);
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(400, 800),
        builder: (_, _) => const GetMaterialApp(home: HomeScreen()),
      ),
    );
    await tester.pump();
  }

  setUp(() => service = _Home());

  test('greeting follows the time of day', () {
    expect(HomeController.greeting(DateTime(2026, 1, 1, 8)), 'Good morning');
    expect(HomeController.greeting(DateTime(2026, 1, 1, 13)), 'Good afternoon');
    expect(HomeController.greeting(DateTime(2026, 1, 1, 20)), 'Good evening');
    expect(HomeController.firstNameOf('  Maria  Lopez '), 'Maria');
    expect(HomeController.firstNameOf(''), '');
  });

  testWidgets('greets, shows today, the map card and today\'s homes', (
    tester,
  ) async {
    final now = DateTime.now();
    service.neighborhood.assignAll([
      for (var i = 1; i <= 20; i++) home(i, prayedAt: i <= 2 ? now : null),
    ]);
    await pump(tester);

    expect(
      find.textContaining(RegExp(r'^Good (morning|afternoon|evening), Maria$')),
      findsOneWidget,
    );
    expect(find.text('2/20'), findsOneWidget);
    expect(find.text('2 of 5 prayed today'), findsOneWidget);
    expect(find.text('Nearest 20 homes'), findsOneWidget);
    expect(find.byKey(const ValueKey('home-view-all')), findsOneWidget);
    expect(find.text('View all 20'), findsOneWidget);

    // Today: the 2 prayed plus the next 3 nearest.
    for (final id in ['h1', 'h2', 'h3', 'h4', 'h5']) {
      await tester.scrollUntilVisible(
        find.byKey(ValueKey('home-today-$id')),
        200,
      );
      expect(find.byKey(ValueKey('home-today-$id')), findsOneWidget);
    }
    expect(find.byKey(const ValueKey('home-today-h6')), findsNothing);

    await tester.ensureVisible(find.byKey(const ValueKey('pray-chip-h3')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('pray-chip-h3')));
    expect(service.prayed, ['h3']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('no search card or size slider on Home', (tester) async {
    service.neighborhood.assignAll([for (var i = 1; i <= 10; i++) home(i)]);
    await pump(tester);
    expect(find.byType(TextField), findsNothing);
    expect(find.byType(Slider), findsNothing);
  });

  testWidgets('area not available: message, states and change address', (
    tester,
  ) async {
    service.homeUnavailable.value = true;
    await pump(tester);
    expect(find.byKey(const ValueKey('home-unavailable')), findsOneWidget);
    expect(find.text("This area isn't available yet"), findsOneWidget);
    expect(find.text('Available now: New Jersey, California'), findsOneWidget);
    expect(find.text('Change home address'), findsOneWidget);
  });

  testWidgets('without a home address it asks for one', (tester) async {
    await pump(tester, profile: user(located: false));
    expect(find.text('Set your home address'), findsOneWidget);
  });

  testWidgets('a finished round says so instead of rows', (tester) async {
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    service.neighborhood.assignAll([
      for (var i = 1; i <= 5; i++) home(i, prayedAt: yesterday),
    ]);
    await pump(tester);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('home-round-complete')),
      200,
    );
    expect(find.byKey(const ValueKey('home-round-complete')), findsOneWidget);
    expect(find.byKey(const ValueKey('home-today-h1')), findsNothing);
  });
}
