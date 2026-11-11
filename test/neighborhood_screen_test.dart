import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:gps_cielo/core/models/user_model.dart';
import 'package:gps_cielo/core/services/household_store.dart';
import 'package:gps_cielo/features/neighborhood/domain/services/neighborhood_service.dart';
import 'package:gps_cielo/features/neighborhood/presentation/controllers/neighborhood_controller.dart';
import 'package:gps_cielo/features/neighborhood/presentation/pages/neighborhood_screen.dart';

import 'support/fake_household_repository.dart';

void main() {
  setUp(() => Get.testMode = true);
  tearDown(Get.reset);

  Future<NeighborhoodController> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);

    final repository = FakeHouseholdRepository()..available = 60;
    final store = HouseholdStore(repository, FakeNotificationRepository());
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

  testWidgets('map scrolls away with the page; count and switch stay pinned', (
    tester,
  ) async {
    final c = await pump(tester);
    expect(find.text('My Neighborhood'), findsWidgets);
    final mapCard = find.text('Set your address to see your neighborhood map');
    expect(mapCard, findsOneWidget);
    final pinnedBefore = tester.getTopLeft(
      find.byKey(const ValueKey('area-count')),
    );

    await tester.drag(
      find.byKey(const ValueKey('area-demo_0')),
      const Offset(0, -700),
    );
    await tester.pumpAndSettle();

    // The map is off screen and the list fills it.
    expect(mapCard.hitTestable(), findsNothing);
    // The strip moved up with the collapsing title, then stuck.
    final pinnedAfter = tester.getTopLeft(
      find.byKey(const ValueKey('area-count')),
    );
    expect(pinnedAfter.dy, lessThan(pinnedBefore.dy));
    expect(
      find.byKey(const ValueKey('area-count')).hitTestable(),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('view-mode')).hitTestable(),
      findsOneWidget,
    );
    // The list is the neighborhood: the same 10 homes as Home.
    expect(c.pagedHouseholds.length, 10);
    expect(find.text('10 homes in your neighborhood'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('List mode hides the map', (tester) async {
    await pump(tester);
    await tester.tap(find.text('List'));
    await tester.pumpAndSettle();
    expect(
      find.text('Set your address to see your neighborhood map'),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('area-demo_0')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('scrolling to the end shows every household once', (
    tester,
  ) async {
    final c = await pump(tester);
    await tester.tap(find.text('List'));
    await tester.pumpAndSettle();
    expect(c.hasMore, isFalse); // only the neighborhood until asked
    await tester.fling(
      find.byType(CustomScrollView),
      const Offset(0, -3000),
      4000,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('browse-all')));
    await tester.pumpAndSettle();
    expect(c.showAllInRange.value, isTrue);
    for (var i = 0; i < 30 && c.hasMore; i++) {
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -800));
      await tester.pumpAndSettle();
    }
    expect(c.hasMore, isFalse);
    await tester.fling(
      find.byType(CustomScrollView),
      const Offset(0, -3000),
      4000,
    );
    await tester.pumpAndSettle();
    expect(c.pagedHouseholds.length, 50); // 60 at 100 m steps, 5 km range
    expect(find.text('All 50 households shown'), findsOneWidget);
  });
}
