import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gps_cielo/core/services/push/push_payload.dart';
import 'package:gps_cielo/routes/app_pages.dart';

/// Donations were removed from the app. Nothing may lead to them.
void main() {
  test('no donation screen is registered', () {
    final names = AppPages.pages.map((p) => p.name);
    expect(names.where((n) => n.contains('donat')), isEmpty);
  });

  test('an old /donation link opens the inbox, not a missing screen', () {
    expect(PushPayload.allowedRoutes, isNot(contains('/donation')));
    expect(
      PushPayload.fromData({'route': '/donation'}).route,
      '/notifications',
    );
  });

  test('no app code mentions donations or Stripe', () {
    final hits = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .where((f) {
          final s = f.readAsStringSync().toLowerCase();
          return s.contains('donat') || s.contains('stripe');
        })
        .map((f) => f.path)
        .toList();
    expect(hits, isEmpty);
  });
}
