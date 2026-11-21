import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:gps_cielo/core/constants/app_colors.dart';
import 'package:gps_cielo/core/constants/app_typography.dart';
import 'package:gps_cielo/shared/widgets/household/household_row.dart';

/// Round progress: a gold arc with "12/50" and a caption ("this round").
class ProgressRing extends StatelessWidget {
  const ProgressRing({
    required this.done,
    required this.total,
    this.caption = 'this round',
    this.size = 64,
    this.dark = false,
    super.key,
  });

  final int done;
  final int total;
  final String caption;
  final double size;

  /// White text on a navy background.
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final value = total <= 0 ? 0.0 : (done / total).clamp(0.0, 1.0);
    final complete = total > 0 && done >= total;
    return SizedBox(
      width: size.r,
      height: size.r,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox.expand(
            child: CircularProgressIndicator(
              key: const ValueKey('round-ring'),
              value: value,
              strokeWidth: 5,
              strokeCap: StrokeCap.round,
              backgroundColor: dark
                  ? Colors.white.withValues(alpha: 0.15)
                  : const Color(0xFFE2E8F0),
              valueColor: AlwaysStoppedAnimation(
                complete ? prayedGreen : AppColors.primaryGold,
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.all(9.r),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$done/$total',
                    style: AppTypography.heading(
                      color: dark ? Colors.white : AppColors.textPrimary,
                      fontSize: 14.sp,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    caption,
                    style: AppTypography.body(
                      color: dark
                          ? Colors.white.withValues(alpha: 0.7)
                          : AppColors.textSecondary,
                      fontSize: 9.sp,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One circle per home in today's goal: green with a check when prayed.
class GoalDots extends StatelessWidget {
  const GoalDots({required this.done, required this.total, super.key});

  final int done;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      key: const ValueKey('goal-dots'),
      spacing: 6.w,
      runSpacing: 6.h,
      children: [
        for (var i = 0; i < total; i++)
          Container(
            width: 22.r,
            height: 22.r,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: i < done ? prayedGreen : AppColors.surface,
              border: Border.all(
                color: i < done ? prayedGreen : AppColors.border,
                width: 1.5,
              ),
            ),
            child: Icon(
              Icons.check_rounded,
              size: 13.r,
              color: i < done ? Colors.white : AppColors.border,
            ),
          ),
      ],
    );
  }
}
