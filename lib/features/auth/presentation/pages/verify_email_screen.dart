import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:gps_cielo/core/constants/app_colors.dart';
import 'package:gps_cielo/core/constants/app_typography.dart';
import 'package:gps_cielo/core/utils/system_ui_config.dart';
import 'package:gps_cielo/features/auth/presentation/controllers/verify_email_controller.dart';
import 'package:gps_cielo/shared/widgets/buttons/app_outline_button.dart';
import 'package:gps_cielo/shared/widgets/buttons/app_primary_button.dart';
import 'package:gps_cielo/shared/widgets/layout/app_header.dart';

/// Shown after sign up (and for unverified email sign-ins) until the
/// verification link has been clicked.
class VerifyEmailScreen extends GetView<VerifyEmailController> {
  const VerifyEmailScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiConfig.darkOverlay,
      child: PopScope(
        // Nowhere to go back to: verify, or sign out below.
        canPop: false,
        child: Scaffold(
          backgroundColor: AppColors.surface,
          body: SingleChildScrollView(
            child: Column(
              children: [
                const AppAuthHeader(
                  title: 'Verify your email',
                  subtitle: 'One last step to protect your account',
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(24.w, 28.h, 24.w, 24.h),
                  child: Column(
                    children: [
                      Container(
                        width: 72.r,
                        height: 72.r,
                        decoration: const BoxDecoration(
                          color: Color(0xFFEFF3FA),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.mark_email_unread_outlined,
                          size: 34.r,
                          color: AppColors.primaryNavy,
                        ),
                      ),
                      SizedBox(height: 18.h),
                      Obx(
                        () => Text(
                          controller.linkSent.value
                              ? 'We sent a verification link to'
                              : 'Send a verification link to',
                          textAlign: TextAlign.center,
                          style: AppTypography.body(
                            color: AppColors.textSecondary,
                            fontSize: 14.sp,
                          ),
                        ),
                      ),
                      SizedBox(height: 4.h),
                      Text(
                        controller.email,
                        key: const ValueKey('verify-email-address'),
                        textAlign: TextAlign.center,
                        style: AppTypography.label(
                          color: AppColors.textPrimary,
                          fontSize: 15.sp,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(height: 18.h),
                      Obx(
                        () => _StatusChip(
                          state: controller.isVerified.value
                              ? _Status.verified
                              : controller.isAutoChecking.value
                              ? _Status.waiting
                              : _Status.paused,
                        ),
                      ),
                      SizedBox(height: 22.h),
                      _steps(),
                      SizedBox(height: 24.h),
                      Obx(() {
                        final verified = controller.isVerified.value;
                        return AppPrimaryButton(
                          key: const ValueKey('verify-check'),
                          label: verified
                              ? 'Verified \u2713  Continuing\u2026'
                              : "I've verified my email",
                          // Only a tap shows the loader, never the quiet
                          // background checks.
                          isLoading: controller.isChecking.value && !verified,
                          onPressed: verified ? null : controller.check,
                        );
                      }),
                      SizedBox(height: 12.h),
                      Obx(() {
                        final wait = controller.cooldown.value;
                        final label = wait > 0
                            ? 'Resend email in ${wait}s'
                            : controller.linkSent.value
                            ? 'Resend email'
                            : 'Send verification email';
                        return AppOutlineButton(
                          key: const ValueKey('verify-resend'),
                          label: label,
                          isLoading: controller.isResending.value,
                          onPressed: wait > 0 || controller.isVerified.value
                              ? null
                              : controller.resend,
                        );
                      }),
                      SizedBox(height: 18.h),
                      Text(
                        "Can't find it? Check Spam or Promotions. It comes "
                        'from noreply@gps-cielo.firebaseapp.com.',
                        textAlign: TextAlign.center,
                        style: AppTypography.body(
                          color: AppColors.textSecondary,
                          fontSize: 12.sp,
                          height: 1.4,
                        ),
                      ),
                      SizedBox(height: 8.h),
                      TextButton(
                        key: const ValueKey('verify-sign-out'),
                        onPressed: controller.signOut,
                        child: Text(
                          'Wrong email? Sign out',
                          style: AppTypography.label(
                            color: AppColors.primaryNavy,
                            fontSize: 13.sp,
                            fontWeight: FontWeight.w600,
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
      ),
    );
  }

  Widget _steps() {
    Widget step(int n, String text) => Padding(
      padding: EdgeInsets.only(bottom: 10.h),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 11.r,
            backgroundColor: AppColors.primaryNavy,
            child: Text(
              '$n',
              style: TextStyle(
                color: Colors.white,
                fontSize: 11.sp,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          SizedBox(width: 10.w),
          Expanded(
            child: Text(
              text,
              style: AppTypography.body(
                color: AppColors.textPrimary,
                fontSize: 13.5.sp,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
    return Container(
      padding: EdgeInsets.fromLTRB(14.w, 14.h, 14.w, 4.h),
      decoration: BoxDecoration(
        color: AppColors.inputSurface,
        borderRadius: BorderRadius.circular(14.r),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          step(1, 'Open the email from GPS Para El Cielo.'),
          step(2, 'Tap the verification link.'),
          step(3, 'Come back here. We continue automatically.'),
        ],
      ),
    );
  }
}

enum _Status { waiting, paused, verified }

/// Where verification stands, without a busy spinner.
class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.state});

  final _Status state;

  @override
  Widget build(BuildContext context) {
    final (color, text) = switch (state) {
      _Status.verified => (
        const Color(0xFF2E7D32),
        'Email verified \u00b7 signing you in',
      ),
      _Status.waiting => (
        const Color(0xFFB7791F),
        "Not verified yet \u00b7 we'll continue automatically",
      ),
      _Status.paused => (
        const Color(0xFF64748B),
        "Not verified yet \u00b7 tap the button once you've clicked the link",
      ),
    };
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      child: Container(
        key: ValueKey('status-${state.name}'),
        padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 7.h),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20.r),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (state == _Status.verified)
              Icon(Icons.check_circle_rounded, size: 15.r, color: color)
            else if (state == _Status.waiting)
              _PulseDot(color: color)
            else
              Icon(Icons.schedule_rounded, size: 15.r, color: color),
            SizedBox(width: 8.w),
            Flexible(
              child: Text(
                text,
                textAlign: TextAlign.center,
                style: AppTypography.label(
                  color: color,
                  fontSize: 12.sp,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A soft breathing dot: "waiting", calmer than a spinner.
class _PulseDot extends StatefulWidget {
  const _PulseDot({required this.color});

  final Color color;

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 0.35, end: 1).animate(_c),
      child: Container(
        width: 9.r,
        height: 9.r,
        decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
      ),
    );
  }
}
