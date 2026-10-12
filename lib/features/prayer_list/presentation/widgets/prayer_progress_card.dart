import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:gps_cielo/core/constants/app_colors.dart';
import 'package:gps_cielo/core/constants/app_typography.dart';
import 'package:gps_cielo/core/models/household_model.dart';

class PrayerProgressCard extends StatelessWidget {
  final int cycleCompleted;
  final int cycleTarget;
  final int prayedTodayCount;
  final List<HouseholdModel> todayHouseholds;

  const PrayerProgressCard({
    required this.cycleCompleted,
    required this.cycleTarget,
    required this.prayedTodayCount,
    required this.todayHouseholds,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
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
              Text(
                "Today's Households",
                style: AppTypography.heading(
                  color: AppColors.textPrimary,
                  fontSize: 14.5.sp,
                  fontWeight: FontWeight.w700,
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
                          value: cycleTarget > 0 ? cycleCompleted / cycleTarget : 0,
                          backgroundColor: const Color(0xFFE2E8F0),
                          valueColor: const AlwaysStoppedAnimation(AppColors.primaryGold),
                          strokeWidth: 7,
                        ),
                      ),
                    ),
                    Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '$cycleCompleted/$cycleTarget',
                            style: AppTypography.heading(
                              color: AppColors.textPrimary,
                              fontSize: 12.5.sp,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            'cycle',
                            style: AppTypography.body(
                              color: AppColors.textSecondary,
                              fontSize: 9.5.sp,
                            ),
                          ),
                        ],
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
                      '$prayedTodayCount of ${todayHouseholds.length} prayed today',
                      style: AppTypography.body(
                        color: AppColors.textPrimary,
                        fontSize: 13.sp,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(height: 10.h),
                    Row(
                      children: List.generate(
                        todayHouseholds.length,
                        (i) {
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
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
