import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:gps_cielo/core/constants/app_colors.dart';
import 'package:gps_cielo/core/constants/app_typography.dart';
import 'package:gps_cielo/core/utils/system_ui_config.dart';
import 'package:gps_cielo/core/utils/validators.dart';
import 'package:gps_cielo/features/auth/presentation/controllers/reset_password_controller.dart';
import 'package:gps_cielo/routes/app_routes.dart';
import 'package:gps_cielo/shared/widgets/buttons/app_back_button.dart';
import 'package:gps_cielo/shared/widgets/buttons/app_primary_button.dart';
import 'package:gps_cielo/shared/widgets/inputs/app_text_field.dart';
import 'package:gps_cielo/shared/widgets/layout/app_header.dart';

class ResetPasswordScreen extends GetView<ResetPasswordController> {
  const ResetPasswordScreen({super.key});

  void _showSuccessDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20.r)),
          child: Padding(
            padding: EdgeInsets.all(24.r),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 64.r,
                  height: 64.r,
                  decoration: BoxDecoration(
                    color: AppColors.success.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.check_circle_rounded,
                    color: AppColors.success,
                    size: 36.r,
                  ),
                ),
                SizedBox(height: 20.h),
                Text(
                  'Password Changed!',
                  style: AppTypography.heading(
                    color: AppColors.primaryNavy,
                    fontSize: 20.sp,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: 8.h),
                Text(
                  'Your password has been successfully reset. You can now sign in with your new credentials.',
                  textAlign: TextAlign.center,
                  style: AppTypography.body(
                    color: AppColors.textSecondary,
                    fontSize: 13.sp,
                    height: 1.4,
                  ),
                ),
                SizedBox(height: 24.h),
                AppPrimaryButton(
                  label: 'Back to Sign In',
                  onPressed: () {
                    Get.offAllNamed(AppRoutes.signIn);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiConfig.darkOverlay,
      child: Scaffold(
        backgroundColor: AppColors.surface,
        body: SingleChildScrollView(
          child: Column(
            children: [
              // Header with Back Button
              Stack(
                children: [
                  const AppAuthHeader(
                    title: 'New Password',
                    subtitle: 'Create a new strong password for your account',
                  ),
                  Positioned(
                    top: 48.h,
                    left: 16.w,
                    child: AppBackButton(
                      color: AppColors.textWhite,
                      onPressed: () => Get.back(),
                    ),
                  ),
                ],
              ),

              // Form Area
              Padding(
                padding: EdgeInsets.fromLTRB(24.w, 32.h, 24.w, 24.h),
                child: Form(
                  key: controller.formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // New Password Field
                      Obx(
                        () => AppTextField(
                          label: 'New Password',
                          hint: 'Minimum 8 characters',
                          controller: controller.passwordController,
                          isPassword: true,
                          isPasswordVisible: controller.isPasswordVisible.value,
                          onPasswordVisibilityPressed: controller.togglePasswordVisibility,
                          textInputAction: TextInputAction.next,
                          validator: (value) => AppValidator.password(value, minLength: 8),
                        ),
                      ),

                      SizedBox(height: 20.h),

                      // Confirm Password Field
                      Obx(
                        () => AppTextField(
                          label: 'Confirm New Password',
                          hint: 'Re-enter your new password',
                          controller: controller.confirmPasswordController,
                          isPassword: true,
                          isPasswordVisible: controller.isConfirmPasswordVisible.value,
                          onPasswordVisibilityPressed: controller.toggleConfirmPasswordVisibility,
                          textInputAction: TextInputAction.done,
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Please confirm your password';
                            }
                            if (value != controller.passwordController.text) {
                              return 'Passwords do not match';
                            }
                            return null;
                          },
                        ),
                      ),

                      SizedBox(height: 20.h),

                      // Password requirements note
                      Container(
                        padding: EdgeInsets.all(14.r),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(12.r),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.info_outline_rounded,
                              color: AppColors.primaryNavy,
                              size: 18.r,
                            ),
                            SizedBox(width: 10.w),
                            Expanded(
                              child: Text(
                                'Must contain at least 8 characters with letters and numbers.',
                                style: AppTypography.body(
                                  color: AppColors.textSecondary,
                                  fontSize: 12.sp,
                                  height: 1.3,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      SizedBox(height: 32.h),

                      // Reset Password CTA
                      Obx(
                        () => AppPrimaryButton(
                          label: 'Reset Password \u2192',
                          isLoading: controller.isLoading.value,
                          onPressed: () async {
                            final success = await controller.resetPassword();
                            if (success && context.mounted) {
                              _showSuccessDialog(context);
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
