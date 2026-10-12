import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:gps_cielo/core/constants/app_colors.dart';
import 'package:gps_cielo/core/constants/app_typography.dart';
import 'package:gps_cielo/core/utils/system_ui_config.dart';
import 'package:gps_cielo/features/auth/presentation/controllers/forgot_password_controller.dart';
import 'package:gps_cielo/shared/widgets/buttons/app_back_button.dart';
import 'package:gps_cielo/shared/widgets/buttons/app_primary_button.dart';
import 'package:gps_cielo/shared/widgets/inputs/app_phone_input_field.dart';
import 'package:gps_cielo/shared/widgets/layout/app_header.dart';

class ForgotPasswordScreen extends GetView<ForgotPasswordController> {
  const ForgotPasswordScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiConfig.darkOverlay,
      child: Scaffold(
        backgroundColor: AppColors.surface,
        body: SingleChildScrollView(
          child: Column(
            children: [
              // Navy Auth Header with Back Button
              Stack(
                children: [
                  const AppAuthHeader(
                    title: 'Forgot Password',
                    subtitle:
                        'Enter your phone number to receive a recovery code',
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

              // Form Body
              Padding(
                padding: EdgeInsets.fromLTRB(24.w, 32.h, 24.w, 24.h),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'We will send a 6-digit verification code by SMS to the phone number linked to your account.',
                      style: AppTypography.body(
                        color: AppColors.textSecondary,
                        fontSize: 14.sp,
                        height: 1.4,
                      ),
                    ),

                    SizedBox(height: 24.h),

                    // Phone Field
                    AppPhoneInputField(
                      label: 'Phone Number',
                      hint: 'Enter your phone number',
                      controller: controller.phoneController,
                      initialCountryCode: 'US',
                      onChanged: (phone) {
                        controller.updatePhoneNumber(phone.completeNumber);
                      },
                    ),

                    SizedBox(height: 32.h),

                    // Send OTP Button
                    Obx(
                      () => AppPrimaryButton(
                        label: 'Send Verification Code',
                        isLoading: controller.isLoading.value,
                        onPressed: controller.sendOtp,
                      ),
                    ),

                    SizedBox(height: 24.h),

                    // Remember Password Link
                    Center(
                      child: TextButton(
                        onPressed: () => Get.back(),
                        child: Text(
                          'Remember your password? Sign In',
                          style: AppTypography.label(
                            color: AppColors.primaryNavy,
                            fontSize: 13.sp,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
