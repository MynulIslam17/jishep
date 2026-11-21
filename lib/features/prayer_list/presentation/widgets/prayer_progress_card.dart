import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:gps_cielo/core/constants/app_colors.dart';
import 'package:gps_cielo/core/constants/app_typography.dart';
import 'package:gps_cielo/features/prayer_list/domain/services/prayer_list_service.dart';
import 'package:gps_cielo/shared/widgets/household/household_row.dart';
import 'package:gps_cielo/shared/widgets/household/progress_ring.dart';

/// Figma 3.2: green "Today's goal reached!" with the goal dots, what
/// tomorrow brings, and "Want to pray for more? Next neighbors ›".
class GoalReachedCard extends StatelessWidget {
  const GoalReachedCard({
    required this.plan,
    this.onNextNeighbors,
    this.showingNext = false,
    super.key,
  });

  final PrayerPlan plan;

  /// Shows the next homes not yet prayed for (null: none left).
  final VoidCallback? onNextNeighbors;
  final bool showingNext;

  /// What tomorrow brings, from the neighbors actually left in this round.
  static String tomorrowMessage(PrayerPlan plan) {
    final n = plan.tomorrowCount;
    final neighbors = n == 1 ? 'neighbor' : 'neighbors';
    if (plan.tomorrowIsLast) {
      return n == 1
          ? 'Tomorrow: your last neighbor in this round.'
          : 'Tomorrow: your last $n $neighbors in this round.';
    }
    return 'Tomorrow brings the next $n $neighbors at midnight.';
  }

  @override
  Widget build(BuildContext context) {
    final extra = plan.extraToday;
    return Container(
      key: const ValueKey('today-done'),
      width: double.infinity,
      padding: EdgeInsets.all(16.r),
      decoration: BoxDecoration(
        color: prayedGreenLight,
        borderRadius: BorderRadius.circular(18.r),
        border: Border.all(color: prayedGreen.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34.r,
                height: 34.r,
                decoration: const BoxDecoration(
                  color: prayedGreen,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.check_rounded,
                  color: Colors.white,
                  size: 20.r,
                ),
              ),
              SizedBox(width: 10.w),
              Expanded(
                child: Text(
                  "Today's goal reached!",
                  style: AppTypography.heading(
                    color: const Color(0xFF14532D),
                    fontSize: 16.sp,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 10.h),
          GoalDots(done: plan.countedToday, total: plan.todayGoal),
          SizedBox(height: 10.h),
          Text(
            'Thank you! You prayed for ${plan.prayedToday} '
            '${plan.prayedToday == 1 ? 'neighbor' : 'neighbors'} today'
            '${extra > 0 ? ', $extra above your goal' : ''}. '
            '${tomorrowMessage(plan)}',
            key: const ValueKey('tomorrow-message'),
            style: AppTypography.body(
              color: const Color(0xFF166534),
              fontSize: 12.5.sp,
              height: 1.4,
            ),
          ),
          if (onNextNeighbors != null) ...[
            SizedBox(height: 12.h),
            const Divider(height: 1, color: Color(0xFFBBE5C8)),
            InkWell(
              key: const ValueKey('next-neighbors'),
              onTap: onNextNeighbors,
              child: Padding(
                padding: EdgeInsets.only(top: 12.h),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        showingNext
                            ? 'Hide next neighbors'
                            : 'Want to pray for more?',
                        style: AppTypography.body(
                          color: const Color(0xFF166534),
                          fontSize: 12.5.sp,
                        ),
                      ),
                    ),
                    if (!showingNext)
                      Text(
                        'Next neighbors',
                        style: AppTypography.label(
                          color: prayedGreen,
                          fontSize: 13.sp,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    Icon(
                      showingNext
                          ? Icons.expand_less_rounded
                          : Icons.chevron_right_rounded,
                      size: 20.r,
                      color: prayedGreen,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Figma 3.3: navy "Round complete! 🎉" with this round's prayed / visited /
/// invited counts and a gold "Start new round now".
class RoundCompleteCard extends StatelessWidget {
  const RoundCompleteCard({
    required this.plan,
    required this.visited,
    required this.invited,
    required this.onStartNewRound,
    this.isStarting = false,
    super.key,
  });

  final PrayerPlan plan;
  final int visited;
  final int invited;
  final VoidCallback onStartNewRound;
  final bool isStarting;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('round-complete'),
      width: double.infinity,
      padding: EdgeInsets.all(18.r),
      decoration: BoxDecoration(
        color: AppColors.primaryNavy,
        borderRadius: BorderRadius.circular(20.r),
      ),
      child: Column(
        children: [
          ProgressRing(
            done: plan.cyclePrayed,
            total: plan.cycleTotal,
            caption: 'prayed',
            size: 76,
            dark: true,
          ),
          SizedBox(height: 12.h),
          Text(
            'Round complete! \u{1F389}',
            style: AppTypography.heading(
              color: AppColors.primaryGold,
              fontSize: 20.sp,
              fontWeight: FontWeight.w800,
            ),
          ),
          SizedBox(height: 6.h),
          Text(
            'You prayed for all ${plan.cycleTotal} neighbors. A new round '
            'starts on its own at midnight. Your visits, invitations and '
            'notes are kept.',
            textAlign: TextAlign.center,
            style: AppTypography.body(
              color: Colors.white.withValues(alpha: 0.85),
              fontSize: 12.5.sp,
              height: 1.4,
            ),
          ),
          SizedBox(height: 14.h),
          Row(
            children: [
              _stat('${plan.cyclePrayed}', 'prayed', 'stat-prayed'),
              SizedBox(width: 8.w),
              _stat('$visited', 'visited', 'stat-visited'),
              SizedBox(width: 8.w),
              _stat('$invited', 'invited', 'stat-invited'),
            ],
          ),
          SizedBox(height: 16.h),
          SizedBox(
            width: double.infinity,
            height: 48.h,
            child: ElevatedButton(
              key: const ValueKey('start-new-cycle'),
              onPressed: isStarting ? null : onStartNewRound,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryGold,
                foregroundColor: AppColors.primaryNavy,
                disabledBackgroundColor: AppColors.primaryGold.withValues(
                  alpha: 0.6,
                ),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14.r),
                ),
              ),
              child: isStarting
                  ? SizedBox(
                      width: 20.r,
                      height: 20.r,
                      child: const CircularProgressIndicator(
                        strokeWidth: 2.4,
                        color: AppColors.primaryNavy,
                      ),
                    )
                  : Text(
                      'Start new round now',
                      style: AppTypography.label(
                        color: AppColors.primaryNavy,
                        fontSize: 14.sp,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _stat(String value, String label, String key) {
    return Expanded(
      child: Container(
        key: ValueKey(key),
        padding: EdgeInsets.symmetric(vertical: 10.h),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12.r),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: AppTypography.heading(
                color: Colors.white,
                fontSize: 18.sp,
                fontWeight: FontWeight.w800,
              ),
            ),
            Text(
              label,
              style: AppTypography.body(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 11.sp,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
