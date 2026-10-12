import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:gps_cielo/core/di/app_binding.dart';
import 'package:gps_cielo/core/theme/app_theme.dart';
import 'package:gps_cielo/core/utils/system_ui_config.dart';
import 'package:gps_cielo/firebase_options.dart';
import 'package:gps_cielo/routes/app_pages.dart';
import 'package:gps_cielo/routes/route_observer.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await GetStorage.init();
  await SystemUiConfig.init();
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
