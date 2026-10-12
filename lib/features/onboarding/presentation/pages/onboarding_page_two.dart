import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:gps_cielo/core/constants/app_colors.dart';
import 'package:gps_cielo/core/constants/app_typography.dart';
import 'package:gps_cielo/features/onboarding/presentation/widgets/radar_mission_widget.dart';

/// Page 2 of Onboarding: Daily Mission with exact Figma left alignment
class OnboardingPageTwo extends StatefulWidget {
  const OnboardingPageTwo({super.key});

  @override
  State<OnboardingPageTwo> createState() => _OnboardingPageTwoState();
}

class _OnboardingPageTwoState extends State<OnboardingPageTwo>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;
  late final Animation<double> _radarFade;
  late final Animation<double> _radarScale;
  late final Animation<double> _textFade;
  late final Animation<Offset> _textSlide;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );

    // 1. Radar Graphic Pop (0.00 -> 0.60)
    _radarFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animController,
        curve: const Interval(0.0, 0.55, curve: Curves.easeIn),
      ),
    );
    _radarScale = Tween<double>(begin: 0.75, end: 1.0).animate(
      CurvedAnimation(
        parent: _animController,
        curve: const Interval(0.0, 0.60, curve: Curves.easeOutBack),
      ),
    );

    // 2. Left-aligned Text Slide & Fade (0.35 -> 1.00)
    _textFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animController,
        curve: const Interval(0.35, 1.00, curve: Curves.easeIn),
      ),
    );
    _textSlide = Tween<Offset>(
      begin: const Offset(0.0, 0.15),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _animController,
        curve: const Interval(0.35, 1.00, curve: Curves.easeOutCubic),
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
      padding: EdgeInsets.symmetric(horizontal: 24.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Spacer(flex: 1),

          // Center Radar Graphic
          Center(
            child: FadeTransition(
              opacity: _radarFade,
              child: ScaleTransition(
                scale: _radarScale,
                child: const RadarMissionWidget(size: 230),
              ),
            ),
          ),

          const Spacer(flex: 2),

          // Left-Aligned Text Content
          FadeTransition(
            opacity: _textFade,
            child: SlideTransition(
              position: _textSlide,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // YOUR DAILY MISSION Tag
                  Text(
                    'YOUR DAILY MISSION',
                    style: AppTypography.label(
                      color: const Color(0xFF64748B),
                      fontSize: 11.sp,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.5,
                    ),
                  ),

                  SizedBox(height: 10.h),

                  // Headline: "Pray for your neighbors, one at a time."
                  RichText(
                    text: TextSpan(
                      style: AppTypography.heading(
                        color: AppColors.primaryNavy,
                        fontSize: 30.sp,
                        fontWeight: FontWeight.w900,
                        height: 1.15,
                      ),
                      children: [
                        const TextSpan(text: 'Pray for your\nneighbors, '),
                        TextSpan(
                          text: 'one at a\ntime.',
                          style: AppTypography.heading(
                            color: AppColors.primaryNavy,
                            fontSize: 30.sp,
                            fontWeight: FontWeight.w900,
                            fontStyle: FontStyle.italic,
                            height: 1.15,
                          ),
                        ),
                      ],
                    ),
                  ),

                  SizedBox(height: 12.h),

                  // Subtitle
                  Text(
                    '5 households daily \u00B7 20 per cycle \u00B7 Never the same twice.',
                    style: AppTypography.body(
                      color: const Color(0xFF64748B),
                      fontSize: 13.sp,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ),

          SizedBox(height: 16.h),
        ],
      ),
    );
  }
}
