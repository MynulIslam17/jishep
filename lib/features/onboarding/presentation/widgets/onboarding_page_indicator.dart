import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:gps_cielo/core/constants/app_colors.dart';

/// Animated Dot Indicator for Onboarding Pages (matching Figma screenshot)
class OnboardingPageIndicator extends StatelessWidget {
  const OnboardingPageIndicator({
    required this.currentPage,
    this.pageCount = 2,
    super.key,
  });

  final int currentPage;
  final int pageCount;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(pageCount, (index) {
        final isActive = currentPage == index;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          margin: EdgeInsets.symmetric(horizontal: 4.w),
          width: isActive ? 24.w : 6.r,
          height: 6.r,
          decoration: BoxDecoration(
            color: isActive
                ? AppColors.primaryNavy
                : const Color(0xFFCBD5E1),
            borderRadius: BorderRadius.circular(3.r),
          ),
        );
      }),
    );
  }
}
