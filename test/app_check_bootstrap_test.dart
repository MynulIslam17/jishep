import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gps_cielo/core/services/app_check_bootstrap.dart';

void main() {
  test(
    'release builds use Play Integrity and DeviceCheck (no entitlement)',
    () {
      final p = AppCheckBootstrap.providersFor(debug: false);
      expect(p.isDebug, isFalse);
      expect(p.android, isA<AndroidPlayIntegrityProvider>());
      expect(p.apple, isA<AppleDeviceCheckProvider>());
    },
  );

  test('debug builds use the debug provider, with an optional token', () {
    final p = AppCheckBootstrap.providersFor(debug: true, debugToken: 'tok');
    expect(p.isDebug, isTrue);
    expect(p.android, isA<AndroidDebugProvider>());
    expect((p.android as AndroidDebugProvider).debugToken, 'tok');
    expect((p.apple as AppleDebugProvider).debugToken, 'tok');
    final none = AppCheckBootstrap.providersFor(debug: true);
    expect((none.apple as AppleDebugProvider).debugToken, isNull);
  });

  test('a failing activation never blocks startup', () async {
    // No Firebase app in unit tests: FirebaseAppCheck.instance throws, and
    // activate() must swallow it.
    await AppCheckBootstrap.activate(debug: false);
  });
}
