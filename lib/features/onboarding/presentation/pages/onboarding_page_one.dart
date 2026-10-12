import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:gps_cielo/core/constants/app_assets.dart';
import 'package:gps_cielo/core/constants/app_colors.dart';
import 'package:gps_cielo/core/constants/app_typography.dart';

/// Page 1 of Onboarding: Animated Houses SVG Illustration & Galatians 6:10 Scripture
class OnboardingPageOne extends StatefulWidget {
  const OnboardingPageOne({super.key});

  @override
  State<OnboardingPageOne> createState() => _OnboardingPageOneState();
}

class _OnboardingPageOneState extends State<OnboardingPageOne>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;
  late final Animation<double> _imageFade;
  late final Animation<double> _imageScale;
  late final Animation<double> _textFade;
  late final Animation<Offset> _textSlide;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );

    // 1. Houses SVG Pop & Fade (0.00 -> 0.60)
    _imageFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animController,
        curve: const Interval(0.0, 0.55, curve: Curves.easeIn),
      ),
    );
    _imageScale = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(
        parent: _animController,
        curve: const Interval(0.0, 0.60, curve: Curves.easeOutCubic),
      ),
    );

    // 2. Scripture Text Slide & Fade (0.40 -> 1.00)
    _textFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animController,
        curve: const Interval(0.40, 1.00, curve: Curves.easeIn),
      ),
    );
    _textSlide = Tween<Offset>(
      begin: const Offset(0.0, 0.20),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _animController,
        curve: const Interval(0.40, 1.00, curve: Curves.easeOutCubic),
      ),
    );

    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 28.w),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Spacer(flex: 1),

          // Animated Houses SVG
          FadeTransition(
            opacity: _imageFade,
            child: ScaleTransition(
              scale: _imageScale,
              child: SvgPicture.asset(
                AppAssets.housesIllustration,
                width: 280.w,
                height: 180.h,
                fit: BoxFit.contain,
              ),
            ),
          ),

          SizedBox(height: 36.h),

          // Animated Scripture Section
          FadeTransition(
            opacity: _textFade,
            child: SlideTransition(
              position: _textSlide,
              child: Column(
                children: [
                  // Top Gold Divider
                  Container(width: 48.w, height: 1.5, color: AppColors.primaryGold),

                  SizedBox(height: 24.h),

                  // Scripture Quote
                  Text(
                    '"So then, as we have opportunity,\nlet us do good to everyone."',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.primaryNavy,
                      fontSize: 18.sp,
                      fontStyle: FontStyle.italic,
                      height: 1.4,
                      fontWeight: FontWeight.w500,
                    ),
                  ),

                  SizedBox(height: 16.h),

                  // Scripture Reference
                  Text(
                    'GALATIANS 6:10',
                    style: AppTypography.heading(
                      color: AppColors.primaryGold,
                      fontSize: 13.sp,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.8,
                    ),
                  ),

                  SizedBox(height: 24.h),

                  // Bottom Gold Divider
                  Container(width: 48.w, height: 1.5, color: AppColors.primaryGold),
                ],
              ),
            ),
          ),

          const Spacer(flex: 2),
        ],
      ),
    );
  }
}
