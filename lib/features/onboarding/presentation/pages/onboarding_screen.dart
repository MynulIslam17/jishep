import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:gps_cielo/core/constants/app_colors.dart';
import 'package:gps_cielo/core/constants/app_typography.dart';
import 'package:gps_cielo/core/utils/system_ui_config.dart';
import 'package:gps_cielo/features/onboarding/presentation/controllers/onboarding_controller.dart';
import 'package:gps_cielo/features/onboarding/presentation/pages/onboarding_page_one.dart';
import 'package:gps_cielo/features/onboarding/presentation/pages/onboarding_page_two.dart';
import 'package:gps_cielo/features/onboarding/presentation/widgets/onboarding_page_indicator.dart';
import 'package:gps_cielo/shared/widgets/buttons/app_primary_button.dart';

class OnboardingScreen extends GetView<OnboardingController> {
  const OnboardingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiConfig.lightOverlay,
      child: Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        body: SafeArea(
          child: Column(
            children: [
              // Top Bar with Skip Action
              _buildTopBar(),

              // PageView with Modular Onboarding Pages
              Expanded(
                child: PageView(
                  controller: controller.pageController,
                  onPageChanged: controller.onPageChanged,
                  children: const [
                    OnboardingPageOne(),
                    OnboardingPageTwo(),
                  ],
                ),
              ),

              // Bottom Area: CTA & Animated Dot Indicator
              _buildBottomSection(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 8.h),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const SizedBox(width: 48),
          Obx(
            () => controller.currentPage.value == 0
                ? TextButton(
                    onPressed: controller.skip,
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFF94A3B8),
                    ),
                    child: Text(
                      'Skip',
                      style: AppTypography.label(
                        color: const Color(0xFF94A3B8),
                        fontSize: 14.sp,
                      ),
                    ),
                  )
                : const SizedBox(height: 48),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomSection() {
    return Padding(
      padding: EdgeInsets.fromLTRB(24.w, 8.h, 24.w, 24.h),
      child: Obx(
        () => Column(
          children: [
            // Get Started Button on Page 2 (Dark Navy with Arrow)
            if (controller.currentPage.value == 1)
              Padding(
                padding: EdgeInsets.only(bottom: 20.h),
                child: AppPrimaryButton(
                  label: 'Get Started \u2192',
                  backgroundColor: AppColors.primaryNavy,
                  textColor: AppColors.textWhite,
                  fontSize: 16,
                  height: 54,
                  borderRadius: 14,
                  onPressed: controller.getStarted,
                ),
              ),

            // 2-Dot Animated Page Indicator
            OnboardingPageIndicator(
              currentPage: controller.currentPage.value,
              pageCount: 2,
            ),
          ],
        ),
      ),
    );
  }
}
