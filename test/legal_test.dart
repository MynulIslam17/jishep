import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:gps_cielo/features/legal/legal_content.dart';
import 'package:gps_cielo/features/legal/legal_html.dart';
import 'package:gps_cielo/features/legal/legal_info.dart';
import 'package:gps_cielo/features/legal/presentation/pages/legal_screen.dart';
import 'package:gps_cielo/features/legal/presentation/widgets/legal_links_text.dart';
import 'package:gps_cielo/routes/app_routes.dart';

void main() {
  group('legal web pages', () {
    test('legal_site/ matches the app text (run tool/build_legal_pages)', () {
      LegalHtml.site().forEach((name, html) {
        final file = File('legal_site/$name');
        expect(file.existsSync(), isTrue, reason: 'legal_site/$name missing');
        expect(
          file.readAsStringSync(),
          html,
          reason:
              'legal_site/$name is stale: dart run tool/build_legal_pages.dart',
        );
      });
    });

    test('pages are escaped and link the contact email', () {
      final html = LegalHtml.page(LegalContent.privacyPolicy);
      expect(html, contains('<title>Privacy Policy'));
      expect(html, contains('<a href="mailto:${LegalInfo.contactEmail}">'));
      expect(html, contains('<a href="https://stripe.com/privacy">'));
      expect(html, contains('&quot;we&quot;'));
    });

    test('firebase hosting serves legal_site with clean URLs', () {
      final config =
          jsonDecode(File('firebase.json').readAsStringSync())
              as Map<String, dynamic>;
      final hosting = config['hosting'] as Map<String, dynamic>;
      expect(hosting['public'], 'legal_site');
      expect(hosting['cleanUrls'], isTrue);
      expect(LegalInfo.privacyUrl, endsWith('/privacy'));
      expect(LegalInfo.termsUrl, endsWith('/terms'));
    });
  });

  group('legal content', () {
    test('covers what the App collects and shares', () {
      final text = _plain(LegalContent.privacyPolicy);
      for (final topic in [
        'location',
        'Stripe',
        'push notification token',
        'Photon',
        'OpenStreetMap',
        'Delete account',
        'do not sell',
        LegalInfo.operatorName,
        LegalInfo.contactEmail,
      ]) {
        expect(text, contains(topic), reason: topic);
      }
    });

    test('terms include the Apple App Store section and governing law', () {
      final text = _plain(LegalContent.termsOfUse);
      expect(text, contains('Apple App Store'));
      expect(text, contains('State of ${LegalInfo.governingState}'));
    });
  });

  group('screens', () {
    Widget app(Widget home) => ScreenUtilInit(
      designSize: const Size(390, 844),
      builder: (_, _) => GetMaterialApp(
        home: home,
        getPages: [
          GetPage(
            name: AppRoutes.terms,
            page: () => const LegalScreen(document: LegalContent.termsOfUse),
          ),
          GetPage(
            name: AppRoutes.privacy,
            page: () => const LegalScreen(document: LegalContent.privacyPolicy),
          ),
        ],
      ),
    );

    tearDown(Get.reset);

    testWidgets('LegalScreen shows the title, date and sections', (
      tester,
    ) async {
      await tester.pumpWidget(
        app(const LegalScreen(document: LegalContent.privacyPolicy)),
      );
      expect(find.text('Privacy Policy'), findsOneWidget);
      expect(find.text(LegalContent.privacyPolicy.lastUpdated), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('16. Contact us'),
        400,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('16. Contact us'), findsOneWidget);
    });

    for (final (label, title) in [
      ('Terms of Use', 'Terms of Use'),
      ('Privacy Policy', 'Privacy Policy'),
    ]) {
      testWidgets('tapping "$label" opens the $title', (tester) async {
        await tester.pumpWidget(
          app(
            const Scaffold(
              body: Center(child: LegalLinksText(prefix: 'I agree to the')),
            ),
          ),
        );
        await tester.tapOnText(find.textRange.ofSubstring(label));
        await tester.pumpAndSettle();
        expect(find.byType(LegalScreen), findsOneWidget);
        final screen = tester.widget<LegalScreen>(find.byType(LegalScreen));
        expect(screen.document.title, title);
      });
    }
  });
}

String _plain(LegalDocument doc) => [
  doc.intro,
  for (final s in doc.sections) ...[
    s.heading,
    for (final b in s.blocks) ...[?b.text, ...?b.bullets],
  ],
].join('\n');
