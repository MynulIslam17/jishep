import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gps_cielo/core/constants/app_colors.dart';
import 'package:gps_cielo/core/utils/app_system_insets.dart';

class SystemUiConfig {
  SystemUiConfig._();

  static const SystemUiOverlayStyle darkOverlay = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarDividerColor: Colors.transparent,
    systemNavigationBarIconBrightness: Brightness.light,
    systemStatusBarContrastEnforced: false,
    systemNavigationBarContrastEnforced: false,
  );

  static const SystemUiOverlayStyle lightOverlay = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    statusBarBrightness: Brightness.light,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarDividerColor: Colors.transparent,
    systemNavigationBarIconBrightness: Brightness.dark,
    systemStatusBarContrastEnforced: false,
    systemNavigationBarContrastEnforced: false,
  );

  static Future<void> init() async {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(lightOverlay);
  }

  static Widget wrapApp(BuildContext context, Widget? child) {
    final media = MediaQuery.of(context);
    final bottom = AppSystemInsets.resolveRawBottom(context);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: lightOverlay,
      child: Column(
        children: [
          Expanded(
            child: MediaQuery(
              data: media.copyWith(
                textScaler: const TextScaler.linear(1),
                size: Size(media.size.width, media.size.height - bottom),
                padding: media.padding.copyWith(bottom: 0),
                viewPadding: media.viewPadding.copyWith(bottom: 0),
              ),
              child: child ?? const SizedBox.shrink(),
            ),
          ),
          if (bottom > 0)
            ColoredBox(
              color: AppColors.background,
              child: SizedBox(height: bottom, width: double.infinity),
            ),
        ],
      ),
    );
  }
}
