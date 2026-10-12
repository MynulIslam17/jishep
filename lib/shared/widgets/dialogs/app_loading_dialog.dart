import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:gps_cielo/core/constants/app_colors.dart';
import 'package:gps_cielo/core/constants/app_typography.dart';

class AppLoadingDialog {
  AppLoadingDialog._();

  static bool _isOpen = false;

  static void show([String message = 'Loading...']) {
    if (_isOpen) return;
    _isOpen = true;

    Get.dialog(
      PopScope(
        canPop: false,
        child: Center(
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 20.h),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16.r),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 36.r,
                  height: 36.r,
                  child: const CircularProgressIndicator(
                    color: AppColors.primaryNavy,
                    strokeWidth: 3,
                  ),
                ),
                SizedBox(height: 16.h),
                Text(
                  message,
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
      barrierDismissible: false,
    );
  }

  static void hide() {
    if (_isOpen) {
      _isOpen = false;
      if (Get.isDialogOpen ?? false) {
        Get.back();
      }
    }
  }
}
