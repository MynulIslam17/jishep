import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:gps_cielo/core/config/feature_flags.dart';
import 'package:gps_cielo/core/models/user_model.dart';
import 'package:gps_cielo/core/services/household_store.dart';
import 'package:gps_cielo/core/services/location_service.dart';
import 'package:gps_cielo/features/neighborhood/domain/services/neighborhood_service.dart';
import 'package:gps_cielo/features/neighborhood/presentation/controllers/neighborhood_controller.dart';
import 'package:gps_cielo/features/neighborhood/presentation/pages/neighborhood_screen.dart';

import 'support/fake_household_repository.dart';

void main() {
  // These tests cover the old `households` path (km range) unless a test
  // turns cell households on; the app default is on.
  setUp(() => FeatureFlags.useCellHouseholds = false);
  tearDown(
    () => FeatureFlags.useCellHouseholds = FeatureFlags.cellHouseholdsDefault,
  );

  setUp(() => Get.testMode = true);
  tearDown(Get.reset);

  late HouseholdStore store;

  Future<NeighborhoodController> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);

    final repository = FakeHouseholdRepository()..available = 60;
    store = HouseholdStore(repository, FakeNotificationRepository());
    await store.bindUser(
      UserModel(
        id: 'alice',
        fullName: 'A',
        email: 'a@example.com',
        address: 'Demra',
        latitude: 23.721,
        longitude: 90.483,
        radiusHomes: 10,
        searchRadiusKm: 5,
      ),
    );
    final controller = Get.put(
      NeighborhoodController(NeighborhoodService(store)),
    );
    // No map tiles in tests: show the map card's placeholder.
    controller.centerLatitude.value = null;

    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (_, _) => const GetMaterialApp(home: NeighborhoodScreen()),
      ),
    );
    await tester.pump();
    return controller;
  }

  testWidgets('map view: chip, legend and the pinned count', (tester) async {
    await pump(tester);
    expect(find.text('My Neighborhood'), findsWidgets);
    expect(
      find.text('Set your address to see your neighborhood map'),
      findsOneWidget,
    );
    expect(find.text('Nearest 10 homes'), findsOneWidget);
    expect(find.text('10 households \u00b7 0 prayed'), findsOneWidget);
    expect(find.text('10 to pray'), findsOneWidget);
    expect(find.text('0 prayed this round'), findsOneWidget);
    expect(find.byKey(const ValueKey('neighborhood-subtitle')), findsOneWidget);
    // Rows are on the List side.
    expect(find.byKey(const ValueKey('area-demo_0')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('list view: numbered rows, nearest first, no browse-all', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.text('List'));
    await tester.pumpAndSettle();
    expect(
      find.text('Set your address to see your neighborhood map'),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('area-demo_0')), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('area-demo_9')),
      300,
    );
    expect(find.byKey(const ValueKey('area-demo_10')), findsNothing);
    expect(find.byKey(const ValueKey('browse-all')), findsNothing);
    // The pinned strip stays on screen after scrolling.
    expect(
      find.byKey(const ValueKey('area-count')).hitTestable(),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('the header search opens the look-around sheet', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const ValueKey('neighborhood-search')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('neighborhood-search-sheet')),
      findsOneWidget,
    );
    expect(find.text('Look around another place'), findsOneWidget);
    expect(find.byKey(const ValueKey('search-back-to-home')), findsNothing);
  });

  testWidgets('looking around shows a banner with the way back home', (
    tester,
  ) async {
    final c = await pump(tester);
    await store.searchAround(
      const ResolvedLocation(
        address: 'Uttara, Dhaka',
        latitude: 23.8759,
        longitude: 90.3795,
        source: LocationSource.search,
      ),
    );
    c.centerLatitude.value = null; // still no tiles
    await tester.pump();
    expect(find.byKey(const ValueKey('viewing-banner')), findsOneWidget);
    expect(find.text('Viewing near Uttara, Dhaka'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('back-to-home')));
    await tester.pumpAndSettle();
    expect(c.isTemporary.value, isFalse);
    expect(find.byKey(const ValueKey('viewing-banner')), findsNothing);
  });
}
