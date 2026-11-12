import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gps_cielo/features/legal/legal_html.dart';
import 'package:gps_cielo/features/profile/presentation/widgets/profile_about_bottom_sheet.dart';

void main() {
  testWidgets('About shows the app name, developer credit and copyright', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(750, 1334); // iPhone SE
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (_, _) => const MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: ProfileAboutBottomSheet(),
            ),
          ),
        ),
      ),
    );
    expect(find.text('Developed by Mynul Islam'), findsOneWidget);
    expect(
      find.text('© 2026 Global Alliance of Christian Churches, Inc.'),
      findsOneWidget,
    );
    expect(find.text('GPS PARA EL CIELO'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  test('every website page footer carries the developer credit', () {
    final pages = LegalHtml.site();
    expect(pages, isNotEmpty);
    for (final entry in pages.entries) {
      if (!entry.key.endsWith('.html')) continue;
      expect(
        entry.value,
        contains('Developed by Mynul Islam'),
        reason: entry.key,
      );
      expect(
        entry.value,
        contains('Global Alliance of Christian Churches, Inc.'),
        reason: entry.key,
      );
    }
  });
}
