import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:gps_cielo/core/di/app_binding.dart';
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
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  await SystemUiConfig.init();
  // The layout is designed for phones held upright.
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const GpsCieloApp());
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
