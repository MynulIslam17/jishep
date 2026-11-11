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
    expect(find.text('12/20 neighbors'), findsOneWidget);
    expect(
      find.text('8 neighbors left \u00b7 about 2 days to go'),
      findsOneWidget,
    );
    expect(find.textContaining('resets at midnight'), findsOneWidget);
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

    // Extra prayers never raise the goal: they are shown apart.
    await pump(tester, PrayerListService.buildPlan(neighborhood, 3));
    expect(find.text('3/3'), findsOneWidget);
    expect(find.text("Today's goal reached!"), findsOneWidget);
    expect(find.text('+2 extra'), findsOneWidget);
    expect(find.text('5/20 neighbors'), findsOneWidget);
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

  testWidgets('8 prayed today with a goal of 5: 5/5 and 3 extra', (
    tester,
  ) async {
    final now = DateTime.now();
    final neighborhood = [
      for (var i = 1; i <= 10; i++) home(i, prayedAt: i <= 8 ? now : null),
    ];
    final plan = PrayerListService.buildPlan(neighborhood, 5, now: now);
    await pump(tester, plan);

    expect(find.text('5/5'), findsOneWidget);
    expect(find.text('+3 extra'), findsOneWidget);
    expect(
      find.text('You prayed for 8 households today, 3 above your goal.'),
      findsOneWidget,
    );
    expect(find.text('8/10 neighbors'), findsOneWidget);
    expect(
      find.text('2 neighbors left \u00b7 about 1 day to go'),
      findsOneWidget,
    );
  });

  testWidgets('the last day of a round: 0/2 and why', (tester) async {
    final now = DateTime.now();
    final yesterday = now.subtract(const Duration(days: 1));
    final neighborhood = [
      for (var i = 1; i <= 10; i++)
        home(i, prayedAt: i <= 8 ? yesterday : null),
    ];
    await pump(tester, PrayerListService.buildPlan(neighborhood, 5, now: now));

    expect(find.text('0/2'), findsOneWidget);
    expect(find.text('This is the last day of this round.'), findsOneWidget);
  });

  testWidgets('a finished round says when the next one starts', (tester) async {
    final now = DateTime.now();
    final neighborhood = [for (var i = 1; i <= 10; i++) home(i, prayedAt: now)];
    await pump(tester, PrayerListService.buildPlan(neighborhood, 5, now: now));

    expect(find.text('10/10 neighbors'), findsOneWidget);
    expect(
      find.text(
        'You prayed for all 10 neighbors! A new round starts at midnight.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('a goal above the neighborhood size is explained', (
    tester,
  ) async {
    final now = DateTime.now();
    final neighborhood = [
      for (var i = 1; i <= 10; i++) home(i, prayedAt: i <= 8 ? now : null),
    ];
    await pump(tester, PrayerListService.buildPlan(neighborhood, 15, now: now));

    expect(find.text('Goal: 15 a day'), findsOneWidget);
    expect(find.text('8/10'), findsOneWidget);
    expect(
      find.text(
        'Your goal is 15 a day, but your neighborhood has only 10 homes. '
        'Show more homes in Prayer preferences.',
      ),
      findsOneWidget,
    );
  });
}
