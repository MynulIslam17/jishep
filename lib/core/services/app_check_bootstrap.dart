import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter/foundation.dart';

/// Firebase App Check: proves to the backend that a request comes from the
/// genuine GPS Para El Cielo app on a real device, not from a script that
/// copied the API key.
///
/// - Android release: **Play Integrity** (needs the app's SHA-256 signing
///   fingerprints registered in Firebase; see docs/APP_CHECK.md).
/// - iOS release: **DeviceCheck**. It needs no entitlement and no change to
///   the provisioning profile, so the existing Codemagic signing
///   (`gps_cielo_appstore_push`) keeps working. App Attest is stronger but
///   needs the App Attest capability + a regenerated profile; see the doc.
/// - Debug builds: the **debug provider**. On first run the native SDK logs
///   a debug token; register it in Firebase Console › App Check › Manage
///   debug tokens, or pass a registered one with
///   `--dart-define=APP_CHECK_DEBUG_TOKEN=<token>`.
///
/// The backend uses the token softly (cached data is served without one;
/// paid Melissa lookups need one), so a device where attestation fails still
/// works. Activation errors never block the app from starting.
class AppCheckBootstrap {
  const AppCheckBootstrap._();

  static const _debugToken = String.fromEnvironment('APP_CHECK_DEBUG_TOKEN');

  /// The providers for this build (pure, for tests).
  static AppCheckProviders providersFor({
    required bool debug,
    String debugToken = '',
  }) {
    if (debug) {
      final token = debugToken.isEmpty ? null : debugToken;
      return AppCheckProviders(
        android: AndroidDebugProvider(debugToken: token),
        apple: AppleDebugProvider(debugToken: token),
        isDebug: true,
      );
    }
    return const AppCheckProviders(
      android: AndroidPlayIntegrityProvider(),
      apple: AppleDeviceCheckProvider(),
      isDebug: false,
    );
  }

  /// Call once, right after `Firebase.initializeApp`.
  static Future<void> activate({
    FirebaseAppCheck? appCheck,
    bool debug = kDebugMode,
  }) async {
    if (kIsWeb) return;
    final providers = providersFor(debug: debug, debugToken: _debugToken);
    try {
      final instance = appCheck ?? FirebaseAppCheck.instance;
      await instance.activate(
        providerAndroid: providers.android,
        providerApple: providers.apple,
      );
      // Refresh tokens in the background before they expire.
      await instance.setTokenAutoRefreshEnabled(true);
    } catch (e) {
      // Never block startup: without a token the backend still serves
      // stored data; only paid lookups are refused.
      debugPrint('App Check activation failed: $e');
    }
  }
}

/// The App Check providers chosen for one build.
class AppCheckProviders {
  const AppCheckProviders({
    required this.android,
    required this.apple,
    required this.isDebug,
  });

  final AndroidAppCheckProvider android;
  final AppleAppCheckProvider apple;
  final bool isDebug;
}
