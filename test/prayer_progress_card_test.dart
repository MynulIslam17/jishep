import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gps_cielo/core/models/household_model.dart';
import 'package:gps_cielo/features/prayer_list/domain/services/prayer_list_service.dart';
import 'package:gps_cielo/features/prayer_list/presentation/widgets/prayer_progress_card.dart';
import 'package:gps_cielo/shared/widgets/household/today_neighbors_card.dart';

HouseholdModel home(int n, {DateTime? prayedAt}) => HouseholdModel(
  id: 'h$n',
  number: n,
  residentName: 'R$n',
  address: 'A',
  isPrayed: prayedAt != null,
  prayedAt: prayedAt,
);

void main() {
  Future<void> pump(WidgetTester tester, Widget child) {
    // A phone screen, like the emulator (1080 x 2400).
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.7;
    addTearDown(tester.view.reset);
    return tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(400, 800),
        builder: (_, _) => MaterialApp(
          home: Scaffold(body: SingleChildScrollView(child: child)),
        ),
      ),
    );
  }

  int dotsDone(WidgetTester tester) => tester
      .widgetList<Icon>(
        find.descendant(
          of: find.byKey(const ValueKey('goal-dots')),
          matching: find.byIcon(Icons.check_rounded),
        ),
      )
      .where((icon) => icon.color == Colors.white)
      .length;

  group('TodayNeighborsCard', () {
    testWidgets('ring is the round; text and dots are today', (tester) async {
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
      await pump(tester, TodayNeighborsCard(plan: plan));

      expect(find.text('12/20'), findsOneWidget);
      expect(find.text('this round'), findsOneWidget);
      expect(find.text('3 of 5 prayed today'), findsOneWidget);
      expect(find.byIcon(Icons.check_rounded), findsNWidgets(5));
      expect(dotsDone(tester), 3);
      expect(
        find.text('8 left this round · about 2 days to go'),
        findsOneWidget,
      );
    });

    testWidgets('extra prayers never raise the goal', (tester) async {
      final now = DateTime.now();
      final neighborhood = [
        for (var i = 1; i <= 10; i++) home(i, prayedAt: i <= 8 ? now : null),
      ];
      await pump(
        tester,
        TodayNeighborsCard(
          plan: PrayerListService.buildPlan(neighborhood, 5, now: now),
        ),
      );
      expect(find.text('5 of 5 prayed today (+3 extra)'), findsOneWidget);
      expect(dotsDone(tester), 5);
    });

    testWidgets('the last day of a round says so', (tester) async {
      final now = DateTime.now();
      final yesterday = now.subtract(const Duration(days: 1));
      final neighborhood = [
        for (var i = 1; i <= 10; i++)
          home(i, prayedAt: i <= 8 ? yesterday : null),
      ];
      await pump(
        tester,
        TodayNeighborsCard(
          plan: PrayerListService.buildPlan(neighborhood, 5, now: now),
        ),
      );
      expect(find.text('0 of 2 prayed today'), findsOneWidget);
      expect(find.text('Last day of this round.'), findsOneWidget);
    });

    testWidgets('a goal above the neighborhood is explained', (tester) async {
      final neighborhood = [for (var i = 1; i <= 10; i++) home(i)];
      await pump(
        tester,
        TodayNeighborsCard(plan: PrayerListService.buildPlan(neighborhood, 15)),
      );
      expect(
        find.text(
          'Your goal is 15 a day, but your neighborhood has only 10 homes.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('a goal of 15 and large text fit', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.6;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final plan = PrayerListService.buildPlan([
        for (var i = 1; i <= 50; i++) home(i),
      ], 15);
      await pump(tester, TodayNeighborsCard(plan: plan, onTap: () {}));
      expect(find.byIcon(Icons.check_rounded), findsNWidgets(15));
      expect(tester.takeException(), isNull);
    });
  });

  group('GoalReachedCard', () {
    testWidgets('thanks, tomorrow, and next neighbors', (tester) async {
      final now = DateTime.now();
      final neighborhood = [
        for (var i = 1; i <= 20; i++) home(i, prayedAt: i <= 7 ? now : null),
      ];
      var tapped = 0;
      await pump(
        tester,
        GoalReachedCard(
          plan: PrayerListService.buildPlan(neighborhood, 5, now: now),
          onNextNeighbors: () => tapped++,
        ),
      );
      expect(find.text("Today's goal reached!"), findsOneWidget);
      expect(
        find.text(
          'Thank you! You prayed for 7 neighbors today, 2 above your goal. '
          'Tomorrow brings the next 5 neighbors at midnight.',
        ),
        findsOneWidget,
      );
      expect(find.text('Want to pray for more?'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('next-neighbors')));
      expect(tapped, 1);
    });

    testWidgets('no next link when nobody is left', (tester) async {
      final now = DateTime.now();
      final neighborhood = [
        for (var i = 1; i <= 6; i++) home(i, prayedAt: i <= 5 ? now : null),
      ];
      await pump(
        tester,
        GoalReachedCard(
          plan: PrayerListService.buildPlan(neighborhood, 5, now: now),
        ),
      );
      expect(find.byKey(const ValueKey('next-neighbors')), findsNothing);
      expect(
        find.textContaining('Tomorrow: your last neighbor in this round.'),
        findsOneWidget,
      );
    });
  });

  testWidgets('RoundCompleteCard shows the stats and starts a round', (
    tester,
  ) async {
    final now = DateTime.now();
    final neighborhood = [for (var i = 1; i <= 10; i++) home(i, prayedAt: now)];
    var started = 0;
    await pump(
      tester,
      RoundCompleteCard(
        plan: PrayerListService.buildPlan(neighborhood, 5, now: now),
        visited: 3,
        invited: 2,
        onStartNewRound: () => started++,
      ),
    );
    expect(find.text('Round complete! \u{1F389}'), findsOneWidget);
    expect(find.text('10/10'), findsOneWidget);
    for (final (key, value) in [
      ('stat-prayed', '10'),
      ('stat-visited', '3'),
      ('stat-invited', '2'),
    ]) {
      expect(
        find.descendant(
          of: find.byKey(ValueKey(key)),
          matching: find.text(value),
        ),
        findsOneWidget,
      );
    }
    await tester.tap(find.text('Start new round now'));
    expect(started, 1);
    expect(tester.takeException(), isNull);
  });

  test('next neighbors: the nearest not yet prayed, after today', () {
    final now = DateTime.now();
    final earlier = now.subtract(const Duration(days: 2));
    final neighborhood = [
      for (var i = 1; i <= 20; i++)
        home(
          i,
          prayedAt: i <= 3
              ? earlier
              : i <= 8
              ? now
              : null,
        ),
    ];
    final plan = PrayerListService.buildPlan(neighborhood, 5, now: now);
    expect(plan.isTodayDone, isTrue);
    final next = PrayerListService.nextNeighbors(neighborhood, plan);
    expect([for (final h in next) h.number], [9, 10, 11, 12, 13]);

    // Near the end of a round only the homes left are offered.
    final almost = [
      for (var i = 1; i <= 7; i++) home(i, prayedAt: i <= 5 ? now : null),
    ];
    final p2 = PrayerListService.buildPlan(almost, 5, now: now);
    expect(
      [for (final h in PrayerListService.nextNeighbors(almost, p2)) h.number],
      [6, 7],
    );
  });
}
