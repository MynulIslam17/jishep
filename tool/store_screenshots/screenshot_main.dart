// App Store screenshots: runs the real app against the LOCAL Firebase
// emulators (seeded by seed_emulator.py) and shows each tab in turn.
// Never used in release builds.
//
//   flutter build ios --simulator --debug -t tool/store_screenshots/screenshot_main.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:gps_cielo/core/utils/system_ui_config.dart';
import 'package:gps_cielo/features/main_nav/presentation/controllers/main_nav_controller.dart';
import 'package:gps_cielo/features/main_nav/presentation/models/main_nav_destination.dart';
import 'package:gps_cielo/firebase_options.dart';
import 'package:gps_cielo/main.dart';

const _host = '127.0.0.1';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  final db = FirebaseFirestore.instance;
  db.useFirestoreEmulator(_host, 8080);
  db.settings = const Settings(persistenceEnabled: false);
  final auth = FirebaseAuth.instance;
  await auth.useAuthEmulator(_host, 9099);
  await auth.signOut();
  await auth.signInWithEmailAndPassword(
    email: 'maria.demo@example.com',
    password: 'screenshots-only-123',
  );

  await SystemUiConfig.init();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const GpsCieloApp());

  await Future<void>.delayed(const Duration(seconds: 20));
  for (final tab in [
    MainNavDestination.neighborhood,
    MainNavDestination.prayerList,
    MainNavDestination.followUp,
    MainNavDestination.profile,
  ]) {
    if (Get.isRegistered<MainNavController>()) {
      Get.find<MainNavController>().changeDestination(tab);
    }
    await Future<void>.delayed(const Duration(seconds: 10));
  }
}
