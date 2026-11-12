import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:gps_cielo/core/constants/app_colors.dart';
import 'package:gps_cielo/core/constants/app_typography.dart';

/// A blocking "working…" dialog: the native iOS activity indicator on iOS,
/// a Material spinner elsewhere. It cannot be dismissed by the user.
class AppLoadingDialog {
  AppLoadingDialog._();

  static Route<void>? _route;

  static bool get isOpen => _route?.isActive ?? false;

  static void show([String message = 'Loading…']) {
    if (isOpen) return;
    final navigator = Get.key.currentState;
    if (navigator == null) return;
    final route = DialogRoute<void>(
      context: navigator.context,
      builder: (_) => AppLoadingIndicatorCard(message: message),
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.35),
    );
    _route = route;
    navigator.push(route);
  }

  /// Removes the dialog, even if it is still animating in.
  static void hide() {
    final route = _route;
    _route = null;
    if (route == null || !route.isActive) return;
    route.navigator?.removeRoute(route);
  }

  /// The dialog was removed by a navigation that replaced the stack.
  static void markClosed() => _route = null;
}

class AppLoadingIndicatorCard extends StatelessWidget {
  const AppLoadingIndicatorCard({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final isIOS = Theme.of(context).platform == TargetPlatform.iOS;
    return PopScope(
      canPop: false,
      child: Center(
        child: Semantics(
          liveRegion: true,
          label: message,
          child: Material(
            color: AppColors.surface,
            elevation: 0,
            borderRadius: BorderRadius.circular(16.r),
            child: Container(
              constraints: BoxConstraints(minWidth: 150.w),
              padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 20.h),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 36.r,
                    height: 36.r,
                    child: Center(
                      child: isIOS
                          ? CupertinoActivityIndicator(radius: 14.r)
                          : const CircularProgressIndicator(
                              color: AppColors.primaryNavy,
                              strokeWidth: 3,
                            ),
                    ),
                  ),
                  SizedBox(height: 14.h),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: AppTypography.body(
                      color: AppColors.textPrimary,
                      fontSize: 14.sp,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
