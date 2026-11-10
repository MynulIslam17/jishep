import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gps_cielo/core/models/household_model.dart';
import 'package:gps_cielo/features/prayer_list/domain/services/prayer_list_service.dart';
import 'package:gps_cielo/features/prayer_list/presentation/widgets/prayer_progress_card.dart';

HouseholdModel home(int n, {DateTime? prayedAt}) => HouseholdModel(
  id: 'h$n',
  number: n,
  residentName: 'R$n',
  address: 'A',
  isPrayed: prayedAt != null,
  prayedAt: prayedAt,
);

void main() {
  Future<void> pump(WidgetTester tester, PrayerPlan plan) {
    // A phone screen, like the emulator (1080 x 2400).
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.7;
    addTearDown(tester.view.reset);
    return tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(400, 800),
        builder: (_, _) => MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: PrayerProgressCard(plan: plan)),
          ),
        ),
      ),
    );
  }

  testWidgets('shows the Settings daily goal, today and the neighborhood', (
    tester,
  ) async {
    final now = DateTime.now();
    final earlier = now.subtract(const Duration(days: 2));
    final neighborhood = [
      for (var i = 1; i <= 20; i++)
        home(
          i,
          prayedAt: i <= 9
              ? earlier
              : i <= 12
              ? now
              : null,
        ),
    ];
    final plan = PrayerListService.buildPlan(neighborhood, 5, now: now);
    await pump(tester, plan);

    expect(find.text('Goal: 5 a day'), findsOneWidget);
    // The ring is today's goal; the cycle is in the text.
    expect(find.text('3/5'), findsOneWidget);
    expect(find.text('today'), findsOneWidget);
    expect(find.text('2 households left to pray for today'), findsOneWidget);
    expect(
      find.textContaining('12 of your 20 neighbors prayed for'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('goal-hint')), findsOneWidget);
    expect(find.byIcon(Icons.check_rounded), findsNWidgets(5));
  });

  testWidgets('the ring follows a new daily goal', (tester) async {
    final now = DateTime.now();
    final neighborhood = [
      for (var i = 1; i <= 20; i++) home(i, prayedAt: i <= 5 ? now : null),
    ];

    await pump(tester, PrayerListService.buildPlan(neighborhood, 10));
    expect(find.text('5/10'), findsOneWidget);

    await pump(tester, PrayerListService.buildPlan(neighborhood, 15));
    expect(find.text('5/15'), findsOneWidget);

    await pump(tester, PrayerListService.buildPlan(neighborhood, 3));
    expect(find.text('5/5'), findsOneWidget);
    expect(find.text("Today's prayers are done!"), findsOneWidget);
    expect(
      find.textContaining('5 of your 20 neighbors prayed for'),
      findsOneWidget,
    );
  });

  testWidgets('a daily goal of 15 fits without overflow', (tester) async {
    final plan = PrayerListService.buildPlan([
      for (var i = 1; i <= 20; i++) home(i),
    ], 15);
    await pump(tester, plan);
    expect(find.byIcon(Icons.check_rounded), findsNWidgets(15));
    expect(tester.takeException(), isNull);
  });

  testWidgets('large system text does not overflow the ring', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.6;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final plan = PrayerListService.buildPlan([
      for (var i = 1; i <= 25; i++) home(i),
    ], 10);
    await pump(tester, plan);
    expect(tester.takeException(), isNull);
  });
}
