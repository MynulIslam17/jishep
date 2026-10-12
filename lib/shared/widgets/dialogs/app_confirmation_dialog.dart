import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:gps_cielo/core/constants/app_colors.dart';
import 'package:gps_cielo/core/constants/app_typography.dart';
import 'package:gps_cielo/shared/widgets/buttons/app_primary_button.dart';

class AppConfirmationDialog extends StatelessWidget {
  const AppConfirmationDialog({
    required this.title,
    required this.message,
    required this.onConfirm,
    this.confirmLabel = 'Confirm',
    this.cancelLabel = 'Cancel',
    this.isDestructive = false,
    super.key,
  });

  final String title;
  final String message;
  final VoidCallback onConfirm;
  final String confirmLabel;
  final String cancelLabel;
  final bool isDestructive;

  static Future<bool?> show({
    required String title,
    required String message,
    required VoidCallback onConfirm,
    String confirmLabel = 'Confirm',
    String cancelLabel = 'Cancel',
    bool isDestructive = false,
  }) {
    return Get.dialog<bool>(
      AppConfirmationDialog(
        title: title,
        message: message,
        onConfirm: onConfirm,
        confirmLabel: confirmLabel,
        cancelLabel: cancelLabel,
        isDestructive: isDestructive,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.r)),
      backgroundColor: AppColors.surface,
      child: Padding(
        padding: EdgeInsets.all(20.r),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: AppTypography.heading(
                color: AppColors.textPrimary,
                fontSize: 18.sp,
                fontWeight: FontWeight.w700,
              ),
            ),
            SizedBox(height: 10.h),
            Text(
              message,
              style: AppTypography.body(
                color: AppColors.textSecondary,
                fontSize: 14.sp,
              ),
            ),
            SizedBox(height: 24.h),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Get.back(result: false),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.textSecondary,
                      padding: EdgeInsets.symmetric(vertical: 12.h),
                    ),
                    child: Text(
                      cancelLabel,
                      style: AppTypography.body(
                        color: AppColors.textSecondary,
                        fontSize: 14.sp,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                SizedBox(width: 12.w),
                Expanded(
                  child: AppPrimaryButton(
                    label: confirmLabel,
                    height: 44,
                    fontSize: 14,
                    backgroundColor: isDestructive ? AppColors.danger : AppColors.primaryNavy,
                    onPressed: () {
                      Get.back(result: true);
                      onConfirm();
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
