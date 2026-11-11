import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gps_cielo/features/profile/presentation/widgets/profile_prayer_preferences_bottom_sheet.dart';

void main() {
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

    // Range: one step left of 5 km is 2 km.
    final range = find.byKey(const ValueKey('range-km-slider'));
    final rangeWidth = tester.getSize(range).width;
    await tester.dragFrom(
      tester.getCenter(range) + Offset(rangeWidth * 0.1, 0),
      Offset(-rangeWidth * 0.17, 0),
    );
    await tester.pump();
    expect(find.text('Within 2 km'), findsOneWidget);

    // Households: 10 -> 20.
    final homes = find.byKey(const ValueKey('default-radius-slider'));
    await tester.drag(homes, Offset(tester.getSize(homes).width * 0.3, 0));
    await tester.pump();
    expect(find.text('Nearest 20 homes'), findsOneWidget);

    await tester.tap(find.text('10 households / day'));
    await tester.pump();
    await tester.tap(find.text('Save Preferences'));
    await tester.pump();
    expect(saved, (10, 20, 2.0));
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
    await tester.tap(find.text('10 households / day'));
    await tester.pump();
    // Rotating / resizing rebuilds the sheet.
    tester.view.physicalSize = const Size(1080, 2300);
    await tester.pumpAndSettle();
    final selected = find.descendant(
      of: find.ancestor(
        of: find.text('10 households / day'),
        matching: find.byType(Row),
      ),
      matching: find.byIcon(Icons.check_rounded),
    );
    expect(selected, findsOneWidget);
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
    expect(find.textContaining('more than your homes'), findsOneWidget);

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
