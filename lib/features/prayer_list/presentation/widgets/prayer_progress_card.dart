import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:gps_cielo/core/constants/app_colors.dart';
import 'package:gps_cielo/core/constants/app_typography.dart';
import 'package:gps_cielo/features/prayer_list/domain/services/prayer_list_service.dart';

/// Today's progress in the ring (prayed of today's households, which follows
/// the daily goal) and the cycle progress in text (households of the
/// neighborhood prayed for in this cycle).
class PrayerProgressCard extends StatelessWidget {
  final PrayerPlan plan;

  const PrayerProgressCard({required this.plan, super.key});

  @override
  Widget build(BuildContext context) {
    final todayHouseholds = plan.today;
    final cycleCompleted = plan.cyclePrayed;
    final cycleTarget = plan.cycleTotal;
    final prayedTodayCount = todayHouseholds.where((h) => h.isPrayed).length;
    // Today's list is the daily goal, or fewer when the cycle is nearly done.
    final todayTotal = todayHouseholds.isNotEmpty
        ? todayHouseholds.length
        : plan.dailyTarget;
    final todayDone = plan.isTodayDone;
    final leftToday = todayTotal - prayedTodayCount;
    final String todayNote;
    if (todayHouseholds.isEmpty) {
      todayNote = 'Nothing to pray for today';
    } else if (todayDone) {
      todayNote = "Today's prayers are done!";
    } else {
      todayNote =
          '$leftToday ${leftToday == 1 ? 'household' : 'households'} '
          'left to pray for today';
    }
    final String cycleNote;
    if (plan.isCycleComplete) {
      cycleNote = 'You have prayed for all $cycleTarget neighbors!';
    } else if (cycleTarget == 0) {
      cycleNote = 'No households in your neighborhood yet.';
    } else {
      final days = plan.daysLeft;
      cycleNote =
          '$cycleCompleted of your $cycleTarget neighbors prayed for '
          '· about $days ${days == 1 ? 'day' : 'days'} to go';
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
                  "Today's Households",
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
                          value: todayTotal > 0
                              ? (prayedTodayCount / todayTotal).clamp(0.0, 1.0)
                              : 0,
                          backgroundColor: const Color(0xFFE2E8F0),
                          valueColor: AlwaysStoppedAnimation(
                            todayDone
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
                                '$prayedTodayCount/$todayTotal',
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
                    SizedBox(height: 4.h),
                    Text(
                      cycleNote,
                      key: const ValueKey('cycle-note'),
                      style: AppTypography.body(
                        color: AppColors.textSecondary,
                        fontSize: 11.5.sp,
                      ),
                    ),
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
          SizedBox(height: 12.h),
          Text(
            'Daily goal, search range and number of neighbors are set in '
            'Profile \u203a Prayer preferences.',
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
