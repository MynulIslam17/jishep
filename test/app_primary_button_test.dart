import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gps_cielo/core/constants/app_colors.dart';
import 'package:gps_cielo/shared/widgets/buttons/app_primary_button.dart';

void main() {
  Future<void> pump(
    WidgetTester tester, {
    required bool loading,
    VoidCallback? onPressed,
  }) {
    return tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(400, 800),
        builder: (_, _) => MaterialApp(
          home: Scaffold(
            body: AppPrimaryButton(
              label: 'Search my neighborhood',
              isLoading: loading,
              onPressed: onPressed,
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('loading shows a spinner on the brand color and blocks taps', (
    tester,
  ) async {
    var taps = 0;
    await pump(tester, loading: true, onPressed: () => taps++);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Search my neighborhood'), findsNothing);

    final material = tester.widget<Material>(
      find.descendant(
        of: find.byType(ElevatedButton),
        matching: find.byType(Material),
      ),
    );
    expect(material.color, AppColors.primaryNavy);

    await tester.tap(find.byType(ElevatedButton));
    expect(taps, 0);
  });

  testWidgets('idle shows the label and handles taps', (tester) async {
    var taps = 0;
    await pump(tester, loading: false, onPressed: () => taps++);
    expect(find.text('Search my neighborhood'), findsOneWidget);
    await tester.tap(find.byType(ElevatedButton));
    expect(taps, 1);
  });
}
