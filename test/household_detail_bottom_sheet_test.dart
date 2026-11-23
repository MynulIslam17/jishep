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
      builder: (context, _) => MaterialApp(home: Scaffold(body: child)),
    );
  }

  testWidgets('Notes section remains open when typing and insets change', (
    WidgetTester tester,
  ) async {
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

  testWidgets('Notes section opens directly when initialOpenNotes is true', (
    WidgetTester tester,
  ) async {
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

  group('recorded owners (Melissa) in the details', () {
    final owned = HouseholdModel(
      id: 'mel:5726833057',
      number: 1,
      ownerName: 'OWNER TEST ONE',
      ownerSecondName: 'OWNER TEST TWO',
      propertyClass: 'Single Family Residential',
      address: '701 TEST AVE',
      cityStateZip: 'CHULA VISTA, CA 91910',
    );

    Future<void> show(WidgetTester tester, HouseholdModel h) async {
      await tester.pumpWidget(
        createTestWidget(child: HouseholdDetailBottomSheet(household: h)),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('owner is the title, the second owner and address below', (
      tester,
    ) async {
      await show(tester, owned);
      expect(find.text('OWNER TEST ONE'), findsOneWidget);
      expect(find.text('OWNER TEST TWO'), findsOneWidget);
      expect(find.text('701 TEST AVE'), findsOneWidget);
      expect(find.text('CHULA VISTA, CA 91910'), findsOneWidget);
      // Clean: no labels, disclaimers, source or classification text.
      for (final t in [
        'Public Record',
        'may not live',
        'Melissa',
        'verified',
        'resident',
        'Single Family',
      ]) {
        expect(find.textContaining(t), findsNothing, reason: t);
      }
    });

    testWidgets(
      'a name the user typed is the title; the owner stays separate',
      (tester) async {
        await show(tester, owned.withName('Maria'));
        expect(find.text('Maria'), findsOneWidget);
        expect(find.text('Owner: OWNER TEST ONE'), findsOneWidget);
        expect(find.text('OWNER TEST TWO'), findsOneWidget);
      },
    );

    testWidgets('no recorded owner: the street address is the title', (
      tester,
    ) async {
      await show(
        tester,
        HouseholdModel(id: 'x', number: 1, address: '9 PLAIN ST'),
      );
      expect(find.text('9 PLAIN ST'), findsOneWidget);
      expect(find.textContaining('Owner'), findsNothing);
    });
  });
}
