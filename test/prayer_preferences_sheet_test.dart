import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gps_cielo/core/config/feature_flags.dart';
import 'package:gps_cielo/features/profile/presentation/widgets/profile_prayer_preferences_bottom_sheet.dart';
import 'package:gps_cielo/shared/widgets/inputs/option_chips.dart';

void main() {
  // These tests cover the old `households` path (km range) unless a test
  // turns cell households on; the app default is on.
  setUp(() => FeatureFlags.useCellHouseholds = false);
  tearDown(
    () => FeatureFlags.useCellHouseholds = FeatureFlags.cellHouseholdsDefault,
  );

  testWidgets('saves the daily target, number of households and the range', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    (int, int, double)? saved;
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(400, 1400),
        builder: (_, _) => MaterialApp(
          home: Scaffold(
            body: ProfilePrayerPreferencesBottomSheet(
              initialTarget: 5,
              initialRadius: 10,
              initialRangeKm: 5,
              onSavePreferences: (target, homes, km) =>
                  saved = (target, homes, km),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Within 5 km'), findsOneWidget);
    expect(find.text('Nearest 10 homes'), findsOneWidget);

    // Range: 5 km -> 2 km.
    await tester.tap(find.byKey(const ValueKey('range-km-2.0')));
    await tester.pump();
    expect(find.text('Within 2 km'), findsOneWidget);

    // Households: 10 -> 25.
    await tester.tap(find.byKey(const ValueKey('homes-25')));
    await tester.pump();
    expect(find.text('Nearest 25 homes'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('goal-10')));
    await tester.pump();
    expect(
      find.text(
        "At 10 a day you'll pray for all 25 neighbors in about 3 days. "
        'Then a new round starts.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Save Preferences'));
    await tester.pump();
    expect(saved, (10, 25, 2.0));
  });

  testWidgets('the households chips reach 50', (tester) async {
    tester.view.physicalSize = const Size(400, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    (int, int, double)? saved;
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(400, 1400),
        builder: (_, _) => MaterialApp(
          home: Scaffold(
            body: ProfilePrayerPreferencesBottomSheet(
              initialTarget: 5,
              initialRadius: 25,
              initialRangeKm: 5,
              onSavePreferences: (target, homes, km) =>
                  saved = (target, homes, km),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('homes-50')));
    await tester.pump();
    expect(find.text('Nearest 50 homes'), findsOneWidget);
    await tester.tap(find.text('Save Preferences'));
    await tester.pump();
    expect(saved, (5, 50, 5.0));
  });

  testWidgets('with cell households there is no km range to pick', (
    tester,
  ) async {
    FeatureFlags.useCellHouseholds = true;
    addTearDown(
      () => FeatureFlags.useCellHouseholds = FeatureFlags.cellHouseholdsDefault,
    );
    tester.view.physicalSize = const Size(400, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    (int, int, double)? saved;
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(400, 1400),
        builder: (_, _) => MaterialApp(
          home: Scaffold(
            body: ProfilePrayerPreferencesBottomSheet(
              initialTarget: 5,
              initialRadius: 50,
              initialRangeKm: 2,
              onSavePreferences: (target, homes, km) =>
                  saved = (target, homes, km),
            ),
          ),
        ),
      ),
    );
    expect(find.byKey(const ValueKey('range-km-2.0')), findsNothing);
    expect(find.text('Search range'), findsNothing);
    expect(find.textContaining('km'), findsNothing);
    expect(find.text('Nearest 50 homes'), findsOneWidget);
    await tester.tap(find.text('Save Preferences'));
    await tester.pump();
    // The stored range is kept as it was.
    expect(saved, (5, 50, 2.0));
  });

  Future<void> openSheet(
    WidgetTester tester, {
    int initialTarget = 5,
    int initialRadius = 10,
    void Function(int, int, double)? onSave,
  }) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.7;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(400, 800),
        builder: (_, _) => MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: TextButton(
                  onPressed: () => ProfilePrayerPreferencesBottomSheet.show(
                    context,
                    initialTarget: initialTarget,
                    initialRadius: initialRadius,
                    onSavePreferences: onSave ?? (_, _, _) {},
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Prayer Preferences'), findsOneWidget);
  }

  testWidgets('the close button closes the sheet', (tester) async {
    await openSheet(tester);
    await tester.tap(find.byKey(const ValueKey('prefs-close')));
    await tester.pumpAndSettle();
    expect(find.text('Prayer Preferences'), findsNothing);
  });

  testWidgets('dragging the sheet down closes it', (tester) async {
    await openSheet(tester);
    await tester.fling(
      find.text('How many households would you like to pray for each day?'),
      const Offset(0, 600),
      2000,
    );
    await tester.pumpAndSettle();
    expect(find.text('Prayer Preferences'), findsNothing);
  });

  testWidgets('a picked goal survives a rebuild', (tester) async {
    await openSheet(tester);
    await tester.tap(find.byKey(const ValueKey('goal-10')));
    await tester.pump();
    // Rotating / resizing rebuilds the sheet.
    tester.view.physicalSize = const Size(1080, 2300);
    await tester.pumpAndSettle();
    final chip = tester.widget<OptionChips>(
      find.ancestor(
        of: find.byKey(const ValueKey('goal-10')),
        matching: find.byType(OptionChips),
      ),
    );
    expect(chip.selected, 10);
  });

  testWidgets('the sheet stays below the status bar', (tester) async {
    tester.view.padding = const FakeViewPadding(top: 300, bottom: 90);
    addTearDown(tester.view.resetPadding);
    await openSheet(tester);
    final top = tester.getTopLeft(
      find.byType(ProfilePrayerPreferencesBottomSheet),
    );
    expect(top.dy, greaterThanOrEqualTo(300 / 2.7));
  });

  testWidgets('a goal larger than the neighborhood cannot be picked', (
    tester,
  ) async {
    int? saved;
    await openSheet(tester, onSave: (target, _, _) => saved = target);
    expect(find.text('Nearest 10 homes'), findsOneWidget);
    expect(find.byKey(const ValueKey('goal-too-big-hint')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('goal-15')));
    await tester.pump();
    await tester.ensureVisible(find.text('Save Preferences'));
    await tester.tap(find.text('Save Preferences'));
    await tester.pump();
    expect(saved, 5);
  });

  testWidgets('a goal saved above the neighborhood opens lowered, with why', (
    tester,
  ) async {
    int? saved;
    await openSheet(
      tester,
      initialTarget: 15,
      onSave: (target, _, _) => saved = target,
    );
    expect(find.byKey(const ValueKey('goal-above-homes')), findsOneWidget);
    expect(
      find.text(
        'Your daily goal is now 10 a day, so it fits the 10 homes in your '
        'neighborhood.',
      ),
      findsOneWidget,
    );
    await tester.ensureVisible(find.text('Save Preferences'));
    await tester.tap(find.text('Save Preferences'));
    await tester.pump();
    expect(saved, 10);
  });
}
