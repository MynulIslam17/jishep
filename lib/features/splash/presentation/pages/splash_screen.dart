import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:get/get.dart';
import 'package:gps_cielo/core/constants/app_assets.dart';
import 'package:gps_cielo/core/constants/app_colors.dart';
import 'package:gps_cielo/core/constants/app_typography.dart';
import 'package:gps_cielo/core/utils/system_ui_config.dart';
import 'package:gps_cielo/features/splash/presentation/controllers/splash_controller.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;

  // Staggered Animations
  late final Animation<double> _logoScale;
  late final Animation<double> _logoFade;
  late final Animation<double> _titleFade;
  late final Animation<Offset> _titleSlide;
  late final Animation<double> _subtitleFade;
  late final Animation<Offset> _subtitleSlide;

  @override
  void initState() {
    super.initState();
    _initAnimations();
  }

  void _initAnimations() {
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1700),
    );

    // 1. Logo Pop Animation (0.00 -> 0.40)
    _logoScale = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(
        parent: _animController,
        curve: const Interval(0.0, 0.40, curve: Curves.easeOutBack),
      ),
    );
    _logoFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animController,
        curve: const Interval(0.0, 0.25, curve: Curves.easeIn),
      ),
    );

    // 2. App Name Slide & Fade (0.35 -> 0.70)
    _titleFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animController,
        curve: const Interval(0.35, 0.70, curve: Curves.easeIn),
      ),
    );
    _titleSlide = Tween<Offset>(
      begin: const Offset(0.0, 0.30),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _animController,
        curve: const Interval(0.35, 0.70, curve: Curves.easeOutCubic),
      ),
    );

    // 3. Subtitle Tagline Slide & Fade (0.65 -> 1.00)
    _subtitleFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animController,
        curve: const Interval(0.65, 1.00, curve: Curves.easeIn),
      ),
    );
    _subtitleSlide = Tween<Offset>(
      begin: const Offset(0.0, 0.35),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _animController,
        curve: const Interval(0.65, 1.00, curve: Curves.easeOutCubic),
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
    // Ensure SplashController is active
    Get.find<SplashController>();

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiConfig.darkOverlay,
      child: Scaffold(
        backgroundColor: AppColors.primaryNavy,
        body: Stack(
          children: [
            const _DotGridBackground(),
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _SplashLogo(scale: _logoScale, fade: _logoFade),
                  SizedBox(height: 28.h),
                  _SplashTitle(slide: _titleSlide, fade: _titleFade),
                  SizedBox(height: 28.h),
                  _SplashSubtitle(slide: _subtitleSlide, fade: _subtitleFade),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// --- Modular Sub-Components ---

class _SplashLogo extends StatelessWidget {
  const _SplashLogo({required this.scale, required this.fade});

  final Animation<double> scale;
  final Animation<double> fade;

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: fade,
      child: ScaleTransition(
        scale: scale,
        child: SvgPicture.asset(
          AppAssets.logoMark,
          width: 88.w,
          height: 104.h,
          fit: BoxFit.contain,
        ),
      ),
    );
  }
}

class _SplashTitle extends StatelessWidget {
  const _SplashTitle({required this.slide, required this.fade});

  final Animation<Offset> slide;
  final Animation<double> fade;

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: fade,
      child: SlideTransition(
        position: slide,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  'GPS ',
                  style: AppTypography.heading(
                    color: AppColors.textWhite,
                    fontSize: 36.sp,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.2,
                  ),
                ),
                Text(
                  'PARA EL',
                  style: AppTypography.heading(
                    color: AppColors.primaryGold,
                    fontSize: 18.sp,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
            Text(
              'CIELO',
              style: AppTypography.heading(
                color: AppColors.textWhite,
                fontSize: 40.sp,
                fontWeight: FontWeight.w900,
                letterSpacing: 2.2,
                height: 0.9,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SplashSubtitle extends StatelessWidget {
  const _SplashSubtitle({required this.slide, required this.fade});

  final Animation<Offset> slide;
  final Animation<double> fade;

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: fade,
      child: SlideTransition(
        position: slide,
        child: Text(
          'CONNECTING HOMES  :  REACHING LIVES',
          style: AppTypography.label(
            color: AppColors.primaryGold.withValues(alpha: 0.85),
            fontSize: 11.sp,
            fontWeight: FontWeight.w600,
            letterSpacing: 2.4,
          ),
        ),
      ),
    );
  }
}

class _DotGridBackground extends StatelessWidget {
  const _DotGridBackground();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.infinite,
      painter: _DotGridPainter(),
    );
  }
}

class _DotGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.07)
      ..style = PaintingStyle.fill;

    const spacing = 32.0;
    const radius = 1.2;

    for (double x = 16.0; x < size.width; x += spacing) {
      for (double y = 16.0; y < size.height; y += spacing) {
        canvas.drawCircle(Offset(x, y), radius, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
