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
import 'package:gps_cielo/shared/widgets/inputs/app_segmented_switch.dart';
import 'package:gps_cielo/shared/widgets/inputs/app_text_field.dart';
import 'package:gps_cielo/core/constants/app_strings.dart';
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
                    subtitle: 'Recover your account by phone or email',
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
                    // Phone (SMS code) or Email (reset link)
                    Obx(
                      () => AppSegmentedSwitch(
                        key: const ValueKey('reset-method'),
                        labels: const ['Phone', 'Email'],
                        icons: const [Icons.sms_outlined, Icons.email_outlined],
                        selectedIndex: controller.useEmail.value ? 1 : 0,
                        onChanged: (i) => controller.setUseEmail(i == 1),
                      ),
                    ),

                    SizedBox(height: 20.h),

                    Obx(() {
                      if (!controller.useEmail.value) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'We will send a 6-digit verification code by '
                              'SMS to the phone number linked to your account.',
                              style: AppTypography.body(
                                color: AppColors.textSecondary,
                                fontSize: 14.sp,
                                height: 1.4,
                              ),
                            ),
                            SizedBox(height: 24.h),
                            AppPhoneInputField(
                              label: 'Phone Number',
                              hint: 'Enter your phone number',
                              controller: controller.phoneController,
                              onChanged: (phone) {
                                controller.updatePhoneNumber(
                                  phone.completeNumber,
                                );
                              },
                            ),
                            SizedBox(height: 32.h),
                            AppPrimaryButton(
                              label: 'Send Verification Code',
                              isLoading: controller.isLoading.value,
                              onPressed: controller.sendOtp,
                            ),
                          ],
                        );
                      }

                      final sentTo = controller.emailSentTo.value;
                      if (sentTo != null) {
                        return Container(
                          key: const ValueKey('reset-email-sent'),
                          width: double.infinity,
                          padding: EdgeInsets.all(16.r),
                          decoration: BoxDecoration(
                            color: AppColors.successLight,
                            borderRadius: BorderRadius.circular(14.r),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.mark_email_read_outlined,
                                    color: AppColors.success,
                                    size: 22.r,
                                  ),
                                  SizedBox(width: 8.w),
                                  Text(
                                    'Check your email',
                                    style: AppTypography.heading(
                                      color: AppColors.textPrimary,
                                      fontSize: 15.sp,
                                    ),
                                  ),
                                ],
                              ),
                              SizedBox(height: 8.h),
                              Text(
                                'If an account uses $sentTo, a link to reset '
                                'the password is on its way. Open it, choose '
                                'a new password, then sign in.',
                                style: AppTypography.body(
                                  color: AppColors.textPrimary,
                                  fontSize: 13.sp,
                                  height: 1.4,
                                ),
                              ),
                              TextButton(
                                onPressed: controller.sendResetEmail,
                                child: const Text('Send it again'),
                              ),
                            ],
                          ),
                        );
                      }

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'We will email you a link to choose a new password.',
                            style: AppTypography.body(
                              color: AppColors.textSecondary,
                              fontSize: 14.sp,
                              height: 1.4,
                            ),
                          ),
                          SizedBox(height: 24.h),
                          AppTextField(
                            label: AppStrings.emailAddress,
                            hint: AppStrings.emailHint,
                            controller: controller.emailController,
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.done,
                          ),
                          SizedBox(height: 32.h),
                          AppPrimaryButton(
                            key: const ValueKey('send-reset-email'),
                            label: 'Email Me a Reset Link',
                            isLoading: controller.isLoading.value,
                            onPressed: controller.sendResetEmail,
                          ),
                        ],
                      );
                    }),

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
