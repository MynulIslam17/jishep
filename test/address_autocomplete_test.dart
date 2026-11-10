import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:gps_cielo/core/services/address_suggestion_service.dart';
import 'package:gps_cielo/shared/widgets/inputs/address_autocomplete.dart';

import 'address_suggestion_service_test.dart' show FakeProvider;

void main() {
  late FakeProvider provider;
  late TextEditingController controller;
  AddressSuggestion? selected;

  setUp(() {
    Get.testMode = true;
    provider = FakeProvider();
    controller = TextEditingController();
    selected = null;
    Get.put<AddressSuggestionService>(
      AddressSuggestionService(provider: provider, minInterval: Duration.zero),
    );
  });

  tearDown(() {
    Get.reset();
    controller.dispose();
  });

  Future<void> pumpField(WidgetTester tester) async {
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(393, 852),
        builder: (context, _) => MaterialApp(
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(16),
              child: AddressAutocomplete(
                controller: controller,
                onSelected: (s) => selected = s,
                fieldBuilder: (context, c, focusNode) =>
                    TextField(controller: c, focusNode: focusNode),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> typeSlowly(WidgetTester tester, List<String> steps) async {
    for (final text in steps) {
      await tester.enterText(find.byType(TextField), text);
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('debounces typing into a single request', (tester) async {
    await pumpField(tester);
    await tester.tap(find.byType(TextField));
    await typeSlowly(tester, ['Dha', 'Dhan', 'Dhanm', 'Dhanmondi']);
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();

    expect(provider.queries, ['Dhanmondi']);
    expect(find.text('Dhanmondi'), findsWidgets);
    expect(find.text('test attribution'), findsOneWidget);
  });

  testWidgets('short queries never hit the network', (tester) async {
    await pumpField(tester);
    await tester.tap(find.byType(TextField));
    await typeSlowly(tester, ['D', 'Dh']);
    await tester.pump(const Duration(milliseconds: 600));
    expect(provider.queries, isEmpty);
  });

  testWidgets(
    'selecting a suggestion fills the field and reports coordinates',
    (tester) async {
      await pumpField(tester);
      await tester.tap(find.byType(TextField));
      await tester.enterText(find.byType(TextField), 'Gulshan');
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Dhaka, Bangladesh'));
      await tester.pumpAndSettle();

      expect(selected?.fullAddress, 'Gulshan, Dhaka, Bangladesh');
      expect(selected?.latitude, 23.75);
      expect(controller.text, 'Gulshan, Dhaka, Bangladesh');
    },
  );

  testWidgets('shows the error state and still allows manual entry', (
    tester,
  ) async {
    provider.error = const AddressSearchException(
      'Address search is unavailable. You can type the address manually.',
    );
    await pumpField(tester);
    await tester.tap(find.byType(TextField));
    await tester.enterText(find.byType(TextField), 'House 5 Road 2');
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();

    expect(find.textContaining('type the address manually'), findsOneWidget);
    expect(controller.text, 'House 5 Road 2');
  });

  testWidgets('shows an empty state when nothing matches', (tester) async {
    Get.replace<AddressSuggestionService>(
      AddressSuggestionService(
        provider: _EmptyProvider(),
        minInterval: Duration.zero,
      ),
    );
    await pumpField(tester);

    await tester.tap(find.byType(TextField));
    await tester.enterText(find.byType(TextField), 'zzzzzz');
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    expect(find.textContaining('No matches found'), findsOneWidget);
  });

  testWidgets('text set by code (GPS / saved address) does not search', (
    tester,
  ) async {
    await pumpField(tester);
    controller.text = 'Road 7, Dhanmondi, Dhaka';
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    expect(provider.queries, isEmpty);
  });
}

class _EmptyProvider extends FakeProvider {
  @override
  Future<List<AddressSuggestion>> search(
    String query, {
    double? nearLatitude,
    double? nearLongitude,
    int limit = 5,
  }) async => const [];
}
