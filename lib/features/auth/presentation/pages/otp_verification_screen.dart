import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:gps_cielo/core/constants/app_colors.dart';
import 'package:gps_cielo/core/constants/app_typography.dart';
import 'package:gps_cielo/core/utils/system_ui_config.dart';
import 'package:gps_cielo/features/auth/presentation/controllers/otp_verification_controller.dart';
import 'package:gps_cielo/shared/widgets/buttons/app_back_button.dart';
import 'package:gps_cielo/shared/widgets/buttons/app_primary_button.dart';
import 'package:gps_cielo/shared/widgets/layout/app_header.dart';

class OtpVerificationScreen extends GetView<OtpVerificationController> {
  const OtpVerificationScreen({super.key});

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
                    title: 'Verification',
                    subtitle: 'Enter the 6-digit code sent to your phone',
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

              // OTP Form Area
              Padding(
                padding: EdgeInsets.fromLTRB(24.w, 32.h, 24.w, 24.h),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      'Code sent to:',
                      style: AppTypography.body(
                        color: AppColors.textSecondary,
                        fontSize: 13.sp,
                      ),
                    ),
                    SizedBox(height: 4.h),
                    Obx(
                      () => Text(
                        controller.phone,
                        style: AppTypography.heading(
                          color: AppColors.primaryNavy,
                          fontSize: 15.sp,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),

                    SizedBox(height: 36.h),

                    // 6-Digit OTP Boxes
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: List.generate(OtpVerificationController.codeLength, (index) {
                        return _buildOtpBox(index);
                      }),
                    ),

                    SizedBox(height: 36.h),

                    // Verify Button
                    Obx(
                      () => AppPrimaryButton(
                        label: 'Verify Code \u2192',
                        isLoading: controller.isLoading.value,
                        onPressed: controller.verifyCode,
                      ),
                    ),

                    SizedBox(height: 28.h),

                    // Resend Timer & Button
                    Obx(
                      () => Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            "Didn't receive the code? ",
                            style: AppTypography.body(
                              color: AppColors.textSecondary,
                              fontSize: 13.sp,
                            ),
                          ),
                          GestureDetector(
                            onTap: controller.countdown.value == 0
                                ? controller.resendCode
                                : null,
                            child: Text(
                              controller.countdown.value > 0
                                  ? 'Resend in 0:${controller.countdown.value.toString().padLeft(2, '0')}'
                                  : 'Resend Code',
                              style: AppTypography.label(
                                color: controller.countdown.value == 0
                                    ? AppColors.primaryGold
                                    : AppColors.textSecondary,
                                fontSize: 13.sp,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
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

  Widget _buildOtpBox(int index) {
    return SizedBox(
      width: 48.r,
      height: 58.r,
      child: TextFormField(
        controller: controller.digitControllers[index],
        focusNode: controller.digitFocusNodes[index],
        keyboardType: TextInputType.number,
        textAlign: TextAlign.center,
        maxLength: 1,
        style: TextStyle(
          fontSize: 22.sp,
          fontWeight: FontWeight.w800,
          color: AppColors.primaryNavy,
        ),
        decoration: InputDecoration(
          counterText: '',
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14.r),
            borderSide: const BorderSide(color: AppColors.border, width: 1.5),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14.r),
            borderSide: const BorderSide(color: AppColors.border, width: 1.5),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14.r),
            borderSide: const BorderSide(color: AppColors.primaryGold, width: 2),
          ),
        ),
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
        ],
        onChanged: (value) {
          final last = OtpVerificationController.codeLength - 1;
          if (value.isNotEmpty && index < last) {
            controller.digitFocusNodes[index + 1].requestFocus();
          } else if (value.isEmpty && index > 0) {
            controller.digitFocusNodes[index - 1].requestFocus();
          }
          if (index == last && value.isNotEmpty) {
            controller.digitFocusNodes[index].unfocus();
            controller.verifyCode();
          }
        },
      ),
    );
  }
}
