import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gps_cielo/core/models/household_model.dart';
import 'package:gps_cielo/shared/widgets/bottom_sheets/household_detail_bottom_sheet.dart';

void main() {
  final testHousehold = HouseholdModel(
    id: '1',
    residentName: 'John Doe',
    address: '123 Main St',
    cityStateZip: 'Dallas, TX 75001',
    number: 1,
    hasFollowUp: false,
    notes: '',
  );

  Widget createTestWidget({required Widget child}) {
    return ScreenUtilInit(
      designSize: const Size(393, 852),
      builder: (context, _) => MaterialApp(
        home: Scaffold(
          body: child,
        ),
      ),
    );
  }

  testWidgets('Notes section remains open when typing and insets change',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      createTestWidget(
        child: HouseholdDetailBottomSheet(
          household: testHousehold,
          initialOpenNotes: false,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Initially notes section is not visible
    expect(find.text('NOTES'), findsNothing);

    // Tap Follow up button to open notes
    await tester.tap(find.text('Follow up'));
    await tester.pumpAndSettle();

    // Notes section is now visible
    expect(find.text('NOTES'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);

    // Enter text into TextField
    await tester.enterText(find.byType(TextField), 'Needs a visit on Saturday');
    await tester.pumpAndSettle();
    expect(find.text('Needs a visit on Saturday'), findsOneWidget);

    // Simulate keyboard showing by changing viewInsets
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pumpAndSettle();

    // Notes section MUST NOT be hidden!
    expect(find.text('NOTES'), findsOneWidget);
    expect(find.text('Needs a visit on Saturday'), findsOneWidget);

    // Reset viewInsets
    tester.view.resetViewInsets();
  });

  testWidgets('Notes section opens directly when initialOpenNotes is true',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      createTestWidget(
        child: HouseholdDetailBottomSheet(
          household: testHousehold.copyWith(notes: 'Existing note'),
          initialOpenNotes: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Notes section is immediately visible with existing note
    expect(find.text('NOTES'), findsOneWidget);
    expect(find.text('Existing note'), findsOneWidget);

    // Simulate keyboard open
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pumpAndSettle();

    // Notes section remains visible
    expect(find.text('NOTES'), findsOneWidget);
    expect(find.text('Existing note'), findsOneWidget);

    tester.view.resetViewInsets();
  });
}
