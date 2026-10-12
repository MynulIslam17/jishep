import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:gps_cielo/core/constants/app_colors.dart';
import 'package:gps_cielo/core/constants/app_strings.dart';
import 'package:gps_cielo/core/constants/app_typography.dart';
import 'package:gps_cielo/core/utils/system_ui_config.dart';
import 'package:gps_cielo/core/utils/validators.dart';
import 'package:gps_cielo/features/auth/presentation/controllers/sign_up_controller.dart';
import 'package:gps_cielo/routes/app_routes.dart';
import 'package:gps_cielo/shared/widgets/buttons/app_back_button.dart';
import 'package:gps_cielo/shared/widgets/buttons/app_primary_button.dart';
import 'package:gps_cielo/shared/widgets/inputs/app_phone_input_field.dart';
import 'package:gps_cielo/shared/widgets/inputs/app_text_field.dart';
import 'package:gps_cielo/shared/widgets/layout/app_header.dart';

class SignUpScreen extends GetView<SignUpController> {
  const SignUpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiConfig.darkOverlay,
      child: Scaffold(
        backgroundColor: AppColors.surface,
        body: SingleChildScrollView(
          child: Column(
            children: [
              // Navy Curved Header with Round Back Button
              Stack(
                children: [
                  const AppAuthHeader(
                    title: AppStrings.createAccount,
                    subtitle: AppStrings.joinGpsCielo,
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
                padding: EdgeInsets.fromLTRB(24.w, 24.h, 24.w, 24.h),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Full Name
                    AppTextField(
                      label: AppStrings.fullName,
                      hint: AppStrings.nameHint,
                      controller: controller.nameController,
                      keyboardType: TextInputType.name,
                      textInputAction: TextInputAction.next,
                      validator: AppValidator.name,
                    ),

                    SizedBox(height: 16.h),

                    // Email Address
                    AppTextField(
                      label: AppStrings.emailAddress,
                      hint: AppStrings.emailHint,
                      controller: controller.emailController,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      validator: AppValidator.email,
                    ),

                    SizedBox(height: 16.h),

                    // Phone Number
                    AppPhoneInputField(
                      label: AppStrings.phoneNumber,
                      hint: AppStrings.phoneHint,
                      controller: controller.phoneController,
                      initialCountryCode: 'US',
                      onChanged: (phone) {
                        controller.updatePhoneNumber(phone.completeNumber);
                      },
                    ),

                    SizedBox(height: 16.h),

                    // Password
                    Obx(
                      () => AppTextField(
                        label: AppStrings.password,
                        hint: AppStrings.passwordMinLength,
                        controller: controller.passwordController,
                        isPassword: true,
                        isPasswordVisible: controller.isPasswordVisible.value,
                        onPasswordVisibilityPressed: controller.togglePasswordVisibility,
                        textInputAction: TextInputAction.done,
                        validator: (val) => AppValidator.password(val, minLength: 8),
                      ),
                    ),

                    SizedBox(height: 16.h),

                    // Terms & Conditions Checkbox
                    Obx(
                      () => Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 24.r,
                            height: 24.r,
                            child: Checkbox(
                              value: controller.agreeToTerms.value,
                              onChanged: (val) => controller.agreeToTerms.value = val ?? false,
                              activeColor: AppColors.primaryNavy,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(4.r),
                              ),
                            ),
                          ),
                          SizedBox(width: 8.w),
                          Expanded(
                            child: Padding(
                              padding: EdgeInsets.only(top: 2.h),
                              child: Text(
                                AppStrings.agreeToTerms,
                                style: AppTypography.body(
                                  color: AppColors.textSecondary,
                                  fontSize: 12.sp,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    SizedBox(height: 24.h),

                    // Create Account Button
                    Obx(
                      () => AppPrimaryButton(
                        label: 'Create account \u2192',
                        isLoading: controller.isLoading.value,
                        onPressed: controller.signUp,
                      ),
                    ),

                    SizedBox(height: 24.h),

                    // Already Have Account Link
                    Center(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            AppStrings.alreadyHaveAccount,
                            style: AppTypography.body(
                              color: AppColors.textSecondary,
                              fontSize: 13.sp,
                            ),
                          ),
                          GestureDetector(
                            onTap: () => Get.offNamed(AppRoutes.signIn),
                            child: Text(
                              AppStrings.signIn,
                              style: AppTypography.label(
                                color: AppColors.primaryNavy,
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
}
