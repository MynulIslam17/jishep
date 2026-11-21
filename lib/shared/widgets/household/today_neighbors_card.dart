import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:gps_cielo/core/constants/app_colors.dart';
import 'package:gps_cielo/core/constants/app_typography.dart';
import 'package:gps_cielo/features/prayer_list/domain/services/prayer_list_service.dart';
import 'package:gps_cielo/shared/widgets/household/progress_ring.dart';

/// Figma "Today's neighbors": the round ring ("12/50 this round"), "2 of 5
/// prayed today" and one dot per home in today's goal. Used on Home and the
/// Prayer List. [onTap] makes the whole card a link (Home → Prayer List).
class TodayNeighborsCard extends StatelessWidget {
  const TodayNeighborsCard({required this.plan, this.onTap, super.key});

  final PrayerPlan plan;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final goal = plan.todayGoal;
    final done = plan.countedToday;
    final extra = plan.extraToday;

    final String? detail;
    if (plan.goalAboveNeighborhood) {
      detail =
          'Your goal is ${plan.dailyTarget} a day, but your neighborhood has '
          'only ${plan.cycleTotal} homes.';
    } else if (goal > 0 && goal < plan.dailyTarget) {
      detail = 'Last day of this round.';
    } else if (plan.cycleTotal > 0 && !plan.isCycleComplete) {
      final days = plan.daysLeft;
      detail =
          '${plan.cycleRemaining} left this round · about $days '
          '${days == 1 ? 'day' : 'days'} to go';
    } else {
      detail = null;
    }

    final card = Container(
      key: const ValueKey('today-neighbors-card'),
      padding: EdgeInsets.all(16.r),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18.r),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryNavy.withValues(alpha: 0.06),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          ProgressRing(done: plan.cyclePrayed, total: plan.cycleTotal),
          SizedBox(width: 14.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        "Today's neighbors",
                        style: AppTypography.heading(
                          color: AppColors.textPrimary,
                          fontSize: 15.sp,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    if (onTap != null)
                      Icon(
                        Icons.chevron_right_rounded,
                        size: 20.r,
                        color: AppColors.textMuted,
                      ),
                  ],
                ),
                SizedBox(height: 2.h),
                Text(
                  goal == 0
                      ? (plan.isCycleComplete
                            ? 'Round complete'
                            : 'Nothing to pray for yet')
                      : '$done of $goal prayed today'
                            '${extra > 0 ? ' (+$extra extra)' : ''}',
                  key: const ValueKey('today-count'),
                  style: AppTypography.body(
                    color: AppColors.textSecondary,
                    fontSize: 12.5.sp,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (goal > 0) ...[
                  SizedBox(height: 8.h),
                  GoalDots(done: done, total: goal),
                ],
                if (detail != null) ...[
                  SizedBox(height: 8.h),
                  Text(
                    detail,
                    key: const ValueKey('today-detail'),
                    style: AppTypography.body(
                      color: AppColors.textMuted,
                      fontSize: 11.sp,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
    if (onTap == null) return card;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: card,
    );
  }
}
