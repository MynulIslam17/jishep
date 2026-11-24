import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:gps_cielo/core/di/app_binding.dart';
import 'package:gps_cielo/core/services/app_check_bootstrap.dart';
import 'package:gps_cielo/core/services/push/push_inbox.dart';
import 'package:gps_cielo/core/services/push/push_messaging_client.dart';
import 'package:gps_cielo/core/theme/app_theme.dart';
import 'package:gps_cielo/core/utils/system_ui_config.dart';
import 'package:gps_cielo/firebase_options.dart';
import 'package:gps_cielo/routes/app_pages.dart';
import 'package:gps_cielo/routes/route_observer.dart';

/// Runs for data messages received while the app is in the background.
/// Notification messages are shown by the system without it. On iOS it may
/// not run at all (e.g. after the app was force-quit), so nothing important
/// depends on it.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  // Android: keep a push that arrives in the background in the in-app inbox,
  // so the unread badge counts it before it is tapped. Best effort.
  try {
    final auth = FirebaseAuth.instance;
    final user =
        auth.currentUser ??
        await auth.authStateChanges().first.timeout(const Duration(seconds: 5));
    if (user != null) {
      await PushInbox().recordReceived(
        user.uid,
        PushMessage.fromRemote(message),
      );
    }
  } catch (_) {}
}

/// Debug builds only (release builds ignore both):
/// - `--dart-define=FIREBASE_EMULATOR_HOST=10.0.2.2` (Android emulator) or
///   `localhost` (iOS simulator): Auth, Firestore and Cloud Functions all
///   use the local Firebase emulators. Nothing touches production.
/// - `--dart-define=FUNCTIONS_EMULATOR_HOST=<mac>.local`: only Cloud
///   Function calls (Melissa address checks) go to the Mac's emulator.
Future<void> _useLocalFunctionsIfAsked() async {
  if (!kDebugMode) return;
  const all = String.fromEnvironment('FIREBASE_EMULATOR_HOST');
  const functionsOnly = String.fromEnvironment('FUNCTIONS_EMULATOR_HOST');
  if (all.isNotEmpty) {
    // Never mix production into a local run: the on-disk Firestore cache
    // and a saved sign-in survive from earlier production runs on the same
    // simulator. No disk cache here, and a session the local Auth emulator
    // does not know is signed out (sign in with a local test account).
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: false,
    );
    await FirebaseAuth.instance.useAuthEmulator(all, 9099);
    FirebaseFirestore.instance.useFirestoreEmulator(all, 8080);
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        await user.reload();
      } catch (_) {
        await FirebaseAuth.instance.signOut();
      }
    }
  }
  final functionsHost = all.isNotEmpty ? all : functionsOnly;
  if (functionsHost.isEmpty) return;
  FirebaseFunctions.instanceFor(
    region: 'us-central1',
  ).useFunctionsEmulator(functionsHost, 5001);
}

void main() async {
  await bootstrap();
  runApp(const GpsCieloApp());
}

/// Everything [main] does before `runApp` (also used by the integration
/// tests, which sign in to the local emulator in between).
Future<void> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  // Before any Firestore / Functions call, so every request carries a token.
  await AppCheckBootstrap.activate();
  await _useLocalFunctionsIfAsked();
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  await SystemUiConfig.init();
  // The layout is designed for phones held upright.
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
}

class GpsCieloApp extends StatelessWidget {
  const GpsCieloApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ScreenUtilInit(
      designSize: const Size(393, 852),
      minTextAdapt: true,
      splitScreenMode: true,
      builder: (context, child) {
        return GetMaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'GPS Para El Cielo',
          theme: AppThemes.lightTheme,
          darkTheme: AppThemes.darkTheme,
          themeMode: ThemeMode.light,
          initialBinding: AppBinding(),
          getPages: AppPages.pages,
          initialRoute: AppPages.initialRoute,
          navigatorObservers: [routeObserver],
          builder: SystemUiConfig.wrapApp,
        );
      },
    );
  }
}
