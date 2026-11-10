import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:gps_cielo/core/constants/app_colors.dart';
import 'package:gps_cielo/core/constants/app_strings.dart';
import 'package:gps_cielo/core/constants/app_typography.dart';
import 'package:gps_cielo/core/utils/system_ui_config.dart';
import 'package:gps_cielo/core/utils/validators.dart';
import 'package:gps_cielo/features/auth/presentation/controllers/sign_in_controller.dart';
import 'package:gps_cielo/routes/app_routes.dart';
import 'package:gps_cielo/shared/widgets/buttons/app_outline_button.dart';
import 'package:gps_cielo/shared/widgets/buttons/apple_sign_in_button.dart';
import 'package:gps_cielo/shared/widgets/buttons/app_primary_button.dart';
import 'package:gps_cielo/shared/widgets/inputs/app_phone_input_field.dart';
import 'package:gps_cielo/shared/widgets/inputs/app_segmented_switch.dart';
import 'package:gps_cielo/shared/widgets/inputs/app_text_field.dart';
import 'package:gps_cielo/shared/widgets/layout/app_header.dart';

class SignInScreen extends GetView<SignInController> {
  const SignInScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiConfig.darkOverlay,
      child: Scaffold(
        backgroundColor: AppColors.surface,
        body: SingleChildScrollView(
          child: Column(
            children: [
              // Navy Curved Header
              const AppAuthHeader(
                title: AppStrings.welcomeBack,
                subtitle: AppStrings.signInToAccount,
              ),

              // Form Area
              Padding(
                padding: EdgeInsets.fromLTRB(24.w, 24.h, 24.w, 24.h),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Login Method Switcher (Email / Phone)
                    Obx(
                      () => AppSegmentedSwitch(
                        key: const ValueKey('login-method'),
                        labels: const ['Email', 'Phone Number'],
                        selectedIndex: controller.isPhoneLogin.value ? 1 : 0,
                        onChanged: (i) => controller.setLoginMode(i == 1),
                      ),
                    ),

                    SizedBox(height: 20.h),

                    // Identifier Field (Email or Phone Input Package)
                    Obx(() {
                      if (controller.isPhoneLogin.value) {
                        return AppPhoneInputField(
                          label: 'Phone Number',
                          hint: 'Enter your phone number',
                          controller: controller.phoneController,
                          onChanged: (phone) {
                            controller.updatePhoneNumber(phone.completeNumber);
                          },
                        );
                      }
                      return AppTextField(
                        label: AppStrings.emailAddress,
                        hint: AppStrings.emailHint,
                        controller: controller.emailController,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        validator: AppValidator.email,
                      );
                    }),

                    SizedBox(height: 16.h),

                    // Password Field (phone sign-in uses an SMS code instead)
                    Obx(
                      () => controller.isPhoneLogin.value
                          ? const SizedBox.shrink()
                          : AppTextField(
                              label: AppStrings.password,
                              hint: AppStrings.passwordHint,
                              controller: controller.passwordController,
                              isPassword: true,
                              isPasswordVisible:
                                  controller.isPasswordVisible.value,
                              onPasswordVisibilityPressed:
                                  controller.togglePasswordVisibility,
                              textInputAction: TextInputAction.done,
                            ),
                    ),

                    // Forgot Password
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () => Get.toNamed(AppRoutes.forgotPassword),
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.symmetric(vertical: 8.h),
                          foregroundColor: AppColors.primaryNavy,
                        ),
                        child: Text(
                          AppStrings.forgotPassword,
                          style: AppTypography.label(
                            color: AppColors.primaryNavy,
                            fontSize: 13.sp,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),

                    SizedBox(height: 12.h),

                    // Sign In Button
                    Obx(
                      () => AppPrimaryButton(
                        label: controller.isPhoneLogin.value
                            ? 'Send Verification Code'
                            : AppStrings.signIn,
                        isLoading:
                            controller.busyWith.value == SignInMethod.form,
                        onPressed: controller.isLoading.value
                            ? null
                            : controller.signIn,
                      ),
                    ),

                    SizedBox(height: 24.h),

                    // Divider
                    Row(
                      children: [
                        const Expanded(
                          child: Divider(color: AppColors.divider),
                        ),
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: 16.w),
                          child: Text(
                            AppStrings.orContinueWith,
                            style: AppTypography.body(
                              color: AppColors.textSecondary,
                              fontSize: 12.sp,
                            ),
                          ),
                        ),
                        const Expanded(
                          child: Divider(color: AppColors.divider),
                        ),
                      ],
                    ),

                    SizedBox(height: 20.h),

                    // Sign in with Apple (iOS only; App Store guideline
                    // 4.8 asks for it next to Google sign-in).
                    if (controller.showAppleSignIn) ...[
                      Obx(
                        () => AppleSignInButton(
                          key: const ValueKey('apple-sign-in'),
                          onPressed: controller.isLoading.value
                              ? null
                              : controller.signInWithApple,
                        ),
                      ),
                      SizedBox(height: 12.h),
                    ],

                    // Google Sign-In Button
                    Obx(
                      () => AppOutlineButton(
                        label: AppStrings.continueWithGoogle,
                        icon: Container(
                          width: 20.r,
                          height: 20.r,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white,
                          ),
                          child: Center(
                            child: Text(
                              'G',
                              style: TextStyle(
                                fontSize: 15.sp,
                                fontWeight: FontWeight.w900,
                                color: const Color(0xFF4285F4),
                              ),
                            ),
                          ),
                        ),
                        onPressed: controller.isLoading.value
                            ? null
                            : controller.signInWithGoogle,
                      ),
                    ),

                    SizedBox(height: 32.h),

                    // Sign Up Link
                    Center(
                      // Wraps instead of overflowing with large text sizes.
                      child: Wrap(
                        alignment: WrapAlignment.center,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            AppStrings.dontHaveAccount,
                            style: AppTypography.body(
                              color: AppColors.textSecondary,
                              fontSize: 13.sp,
                            ),
                          ),
                          GestureDetector(
                            onTap: () => Get.toNamed(AppRoutes.signUp),
                            child: Text(
                              AppStrings.signUp,
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
