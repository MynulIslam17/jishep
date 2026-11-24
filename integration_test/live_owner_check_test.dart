// LIVE PRODUCTION check (gps-para-el-cielo), run on a simulator/emulator
// with a registered App Check DEBUG token. It can spend real Melissa
// credits when paid discovery is ON. Run only with the owner's approval:
//
//   flutter drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/live_owner_check_test.dart \
//     --dart-define=LIVE_CHECK=gps-para-el-cielo \
//     --dart-define=APP_CHECK_DEBUG_TOKEN=<registered debug token> \
//     --dart-define=TEST_EMAIL=... --dart-define=TEST_PASSWORD=...
//
// Credentials and tokens come from .local-backups (never committed).
// Prints counts only (no names, no addresses).
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gps_cielo/main.dart' as app;
import 'package:integration_test/integration_test.dart';

const _live = String.fromEnvironment('LIVE_CHECK');
const _email = String.fromEnvironment('TEST_EMAIL');
const _password = String.fromEnvironment('TEST_PASSWORD');
const _emulator = String.fromEnvironment('FIREBASE_EMULATOR_HOST');

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('live: App Check token accepted, one discoverOwners call', (
    tester,
  ) async {
    expect(_live, 'gps-para-el-cielo', reason: 'explicit live opt-in');
    expect(_emulator, isEmpty, reason: 'this check talks to production');
    expect(_email, isNotEmpty);

    await app.bootstrap();
    final token = await FirebaseAppCheck.instance.getToken(true);
    debugPrint('LIVE appCheckToken=${token != null && token.isNotEmpty}');

    final auth = FirebaseAuth.instance;
    if (auth.currentUser?.email != _email) {
      await auth.signOut();
      await auth.signInWithEmailAndPassword(email: _email, password: _password);
    }

    final result = await FirebaseFunctions.instanceFor(region: 'us-central1')
        .httpsCallable(
          'discoverOwners',
          options: HttpsCallableOptions(timeout: const Duration(seconds: 150)),
        )
        .call<Map<Object?, Object?>>({'target': 50});
    final d = result.data;
    final records = d['records'];
    debugPrint(
      'LIVE result named=${records is List ? records.length : -1} '
      'completeness=${d['completeness']} credits=${d['credits']} '
      'cached=${d['cached']} limited=${d['limited']} queued=${d['queued']} '
      'pending=${d['pending']}',
    );

    await tester.pumpWidget(const app.GpsCieloApp());
    final end = DateTime.now().add(const Duration(seconds: 25));
    while (DateTime.now().isBefore(end)) {
      await tester.pump(const Duration(milliseconds: 500));
    }
    if (defaultTargetPlatform == TargetPlatform.android) {
      await binding.convertFlutterSurfaceToImage();
      await tester.pump();
    }
    await binding.takeScreenshot('live_home');
  });
}
