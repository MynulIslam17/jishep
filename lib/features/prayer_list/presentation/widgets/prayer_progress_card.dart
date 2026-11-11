import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:gps_cielo/core/constants/app_colors.dart';
import 'package:gps_cielo/core/constants/app_typography.dart';
import 'package:gps_cielo/features/prayer_list/domain/services/prayer_list_service.dart';

/// Today's progress toward the daily goal in the ring (extra prayers shown
/// apart, so the goal never changes), then the round: how many neighbors of
/// the whole neighborhood were prayed for in this round.
class PrayerProgressCard extends StatelessWidget {
  final PrayerPlan plan;

  const PrayerProgressCard({required this.plan, super.key});

  @override
  Widget build(BuildContext context) {
    final todayHouseholds = plan.today;
    final cycleCompleted = plan.cyclePrayed;
    final cycleTarget = plan.cycleTotal;
    final goal = plan.todayGoal;
    final counted = plan.countedToday;
    final extra = plan.extraToday;
    final todayDone = plan.isTodayDone;
    final leftToday = plan.leftToday;

    final String todayNote;
    String? todayDetail;
    if (todayDone) {
      todayNote = "Today's goal reached!";
      if (extra > 0) {
        todayDetail =
            'You prayed for ${plan.prayedToday} households today, '
            '$extra above your goal.';
      }
    } else if (goal == 0) {
      todayNote = plan.isCycleComplete
          ? 'Round complete!'
          : 'Nothing to pray for today';
    } else {
      todayNote =
          '$leftToday ${leftToday == 1 ? 'household' : 'households'} '
          'left to pray for today';
      if (plan.goalAboveNeighborhood) {
        todayDetail =
            'Your goal is ${plan.dailyTarget} a day, but your neighborhood '
            'has only $cycleTarget homes. Show more homes in Prayer '
            'preferences.';
      } else if (goal < plan.dailyTarget) {
        todayDetail = 'This is the last day of this round.';
      }
    }

    final String roundNote;
    if (plan.isCycleComplete) {
      roundNote =
          'You prayed for all $cycleTarget neighbors! '
          'A new round starts at midnight.';
    } else if (cycleTarget == 0) {
      roundNote = 'No households in your neighborhood yet.';
    } else {
      final left = plan.cycleRemaining;
      final days = plan.daysLeft;
      roundNote =
          '$left ${left == 1 ? 'neighbor' : 'neighbors'} left '
          '\u00b7 about $days ${days == 1 ? 'day' : 'days'} to go';
    }

    return Container(
      padding: EdgeInsets.all(16.r),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 22.r,
                height: 22.r,
                decoration: const BoxDecoration(
                  color: Color(0xFFFEF3C7),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.access_time_rounded,
                  size: 13.r,
                  color: const Color(0xFFD97706),
                ),
              ),
              SizedBox(width: 8.w),
              Expanded(
                child: Text(
                  "Today's Prayer Goal",
                  style: AppTypography.heading(
                    color: AppColors.textPrimary,
                    fontSize: 14.5.sp,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (plan.dailyTarget > 0)
                Container(
                  key: const ValueKey('daily-goal'),
                  padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 3.h),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF3C7),
                    borderRadius: BorderRadius.circular(20.r),
                  ),
                  child: Text(
                    'Goal: ${plan.dailyTarget} a day',
                    style: AppTypography.body(
                      color: const Color(0xFF92400E),
                      fontSize: 11.sp,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),

          SizedBox(height: 14.h),

          Row(
            children: [
              // Circular Progress Arc
              SizedBox(
                width: 72.r,
                height: 72.r,
                child: Stack(
                  children: [
                    Center(
                      child: SizedBox(
                        width: 72.r,
                        height: 72.r,
                        child: CircularProgressIndicator(
                          key: const ValueKey('today-ring'),
                          value: goal > 0
                              ? (counted / goal).clamp(0.0, 1.0)
                              : (plan.isCycleComplete ? 1 : 0),
                          backgroundColor: const Color(0xFFE2E8F0),
                          valueColor: AlwaysStoppedAnimation(
                            todayDone || plan.isCycleComplete
                                ? const Color(0xFF2E7D32)
                                : AppColors.primaryGold,
                          ),
                          strokeWidth: 7,
                        ),
                      ),
                    ),
                    Center(
                      child: Padding(
                        padding: EdgeInsets.all(10.r),
                        // Shrinks with large system fonts instead of overflowing.
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '$counted/$goal',
                                style: AppTypography.heading(
                                  color: AppColors.textPrimary,
                                  fontSize: 12.5.sp,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              Text(
                                'today',
                                style: AppTypography.body(
                                  color: AppColors.textSecondary,
                                  fontSize: 9.5.sp,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              SizedBox(width: 16.w),

              // Dynamic Prayed Today Text and Checkmark Circles
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      todayNote,
                      key: const ValueKey('prayed-today'),
                      style: AppTypography.body(
                        color: AppColors.textPrimary,
                        fontSize: 13.sp,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (extra > 0) ...[
                      SizedBox(height: 4.h),
                      Container(
                        key: const ValueKey('extra-today'),
                        padding: EdgeInsets.symmetric(
                          horizontal: 8.w,
                          vertical: 2.h,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE8F5E9),
                          borderRadius: BorderRadius.circular(20.r),
                        ),
                        child: Text(
                          '+$extra extra',
                          style: AppTypography.body(
                            color: const Color(0xFF2E7D32),
                            fontSize: 11.sp,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                    if (todayDetail != null) ...[
                      SizedBox(height: 4.h),
                      Text(
                        todayDetail,
                        key: const ValueKey('today-detail'),
                        style: AppTypography.body(
                          color: AppColors.textSecondary,
                          fontSize: 11.5.sp,
                        ),
                      ),
                    ],
                    SizedBox(height: 10.h),
                    // One circle per household on today's list.
                    // Wraps so a daily target of 10-15 never overflows.
                    Wrap(
                      spacing: 0,
                      runSpacing: 6.h,
                      children: List.generate(todayHouseholds.length, (i) {
                        final isDone = todayHouseholds[i].isPrayed;
                        return Container(
                          margin: EdgeInsets.only(right: 8.w),
                          width: 26.r,
                          height: 26.r,
                          decoration: BoxDecoration(
                            color: isDone
                                ? const Color(0xFF2E7D32)
                                : const Color(0xFFE2E8F0),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.check_rounded,
                            size: 15.r,
                            color: isDone
                                ? Colors.white
                                : const Color(0xFF1E293B),
                          ),
                        );
                      }),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (cycleTarget > 0) ...[
            SizedBox(height: 14.h),
            Divider(height: 1, color: AppColors.border),
            SizedBox(height: 12.h),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'This round',
                    style: AppTypography.heading(
                      color: AppColors.textPrimary,
                      fontSize: 13.sp,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  '$cycleCompleted/$cycleTarget neighbors',
                  key: const ValueKey('round-count'),
                  style: AppTypography.body(
                    color: AppColors.textPrimary,
                    fontSize: 12.sp,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            SizedBox(height: 8.h),
            ClipRRect(
              borderRadius: BorderRadius.circular(4.r),
              child: LinearProgressIndicator(
                key: const ValueKey('round-bar'),
                value: (cycleCompleted / cycleTarget).clamp(0.0, 1.0),
                minHeight: 6.h,
                backgroundColor: const Color(0xFFE2E8F0),
                valueColor: const AlwaysStoppedAnimation(Color(0xFF2E7D32)),
              ),
            ),
            SizedBox(height: 6.h),
          ] else
            SizedBox(height: 12.h),
          Text(
            roundNote,
            key: const ValueKey('cycle-note'),
            style: AppTypography.body(
              color: AppColors.textSecondary,
              fontSize: 11.5.sp,
            ),
          ),
          SizedBox(height: 10.h),
          Text(
            'Your daily goal resets at midnight. Goal, search range and '
            'number of neighbors are set in Profile \u203a Prayer preferences.',
            key: const ValueKey('goal-hint'),
            style: AppTypography.body(
              color: AppColors.textSecondary,
              fontSize: 10.5.sp,
            ),
          ),
        ],
      ),
    );
  }
}
