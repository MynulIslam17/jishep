import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:gps_cielo/core/constants/app_colors.dart';
import 'package:gps_cielo/core/constants/app_strings.dart';
import 'package:gps_cielo/core/constants/app_typography.dart';
import 'package:gps_cielo/shared/widgets/buttons/app_primary_button.dart';
import 'package:gps_cielo/features/main_nav/presentation/controllers/main_nav_controller.dart';
import 'package:gps_cielo/features/main_nav/presentation/models/main_nav_destination.dart';
import 'package:gps_cielo/features/profile/presentation/controllers/profile_controller.dart';
import 'package:gps_cielo/features/profile/presentation/widgets/profile_contact_support_bottom_sheet.dart';

/// The primary location is chosen once, at signup (blueprint §2.1). There is
/// no in-app control to change it: a user who moved or picked the wrong
/// address asks support, who corrects it with an audited operator tool
/// (functions/tool/location_admin.js). This replaces the former
/// in-app address editors (removed 2026-11-24).
abstract final class PrimaryLocationHelp {
  /// "Contact support" for empty / unavailable neighborhood states.
  static Widget button({Key? key}) => OutlinedButton.icon(
    key: key ?? const ValueKey('contact-support-location'),
    onPressed: () => contactSupport(Get.context!),
    icon: const Icon(Icons.support_agent_rounded, size: 16),
    label: const Text(AppStrings.contactSupport),
  );

  /// Opens Contact support (from Profile's controller when available).
  static void contactSupport(BuildContext context) {
    if (!Get.isRegistered<ProfileController>()) {
      if (Get.isRegistered<MainNavController>()) {
        Get.find<MainNavController>().changeDestination(
          MainNavDestination.profile,
        );
      }
      return;
    }
    final controller = Get.find<ProfileController>();
    ProfileContactSupportBottomSheet.show(
      context,
      onSendMessage: controller.sendSupportMessage,
    );
  }

  /// Read-only details of the primary location (Profile › Your
  /// neighborhood): the saved address, why it is fixed, and how to ask
  /// support for a correction. Nothing here edits the location.
  static void showDetails(BuildContext context, {required String address}) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheet) => Container(
        key: const ValueKey('primary-location-sheet'),
        padding: EdgeInsets.fromLTRB(
          20.w,
          12.h,
          20.w,
          20.h + MediaQuery.of(sheet).padding.bottom,
        ),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24.r)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40.w,
                height: 4.h,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2.r),
                ),
              ),
            ),
            SizedBox(height: 16.h),
            Text(
              AppStrings.primaryNeighborhood,
              style: AppTypography.heading(
                color: AppColors.textPrimary,
                fontSize: 18.sp,
                fontWeight: FontWeight.w800,
              ),
            ),
            SizedBox(height: 12.h),
            Semantics(
              label: 'Saved neighborhood address: $address',
              child: Container(
                padding: EdgeInsets.all(14.r),
                decoration: BoxDecoration(
                  color: AppColors.primaryNavy.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(14.r),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.location_on_rounded,
                      color: AppColors.primaryNavy,
                      size: 22.r,
                    ),
                    SizedBox(width: 10.w),
                    Expanded(
                      child: Text(
                        address.isEmpty ? 'Not set' : address,
                        style: AppTypography.label(
                          color: AppColors.textPrimary,
                          fontSize: 14.sp,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Icon(
                      Icons.lock_outline_rounded,
                      color: AppColors.textMuted,
                      size: 18.r,
                      semanticLabel: 'Fixed',
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(height: 12.h),
            Text(
              '${AppStrings.primaryLocationFixed} '
              '${AppStrings.primaryLocationHelp}',
              style: AppTypography.body(
                color: AppColors.textSecondary,
                fontSize: 13.sp,
                height: 1.45,
              ),
            ),
            SizedBox(height: 18.h),
            AppPrimaryButton(
              label: AppStrings.contactSupport,
              onPressed: () {
                Navigator.of(sheet).pop();
                contactSupport(context);
              },
            ),
            SizedBox(height: 4.h),
            TextButton(
              onPressed: () => Navigator.of(sheet).pop(),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }
}
