import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:gps_cielo/core/constants/app_colors.dart';
import 'package:gps_cielo/core/constants/app_typography.dart';
import 'package:gps_cielo/core/models/household_model.dart';
import 'package:gps_cielo/shared/widgets/bottom_sheets/household_detail_bottom_sheet.dart';

class PrayerListItemCard extends StatelessWidget {
  final HouseholdModel household;
  final VoidCallback onPrayToggle;
  final ValueChanged<HouseholdModel> onUpdated;

  const PrayerListItemCard({
    required this.household,
    required this.onPrayToggle,
    required this.onUpdated,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        HouseholdDetailBottomSheet.show(
          context,
          household: household,
          onPrayToggle: onPrayToggle,
          onUpdated: onUpdated,
        );
      },
      borderRadius: BorderRadius.circular(16.r),
      child: Container(
        padding: EdgeInsets.all(14.r),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16.r),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Row: Number + Home icon + Resident Info + Chevron
            Row(
              children: [
                // Number Circle Badge
                Container(
                  width: 32.r,
                  height: 32.r,
                  decoration: const BoxDecoration(
                    color: AppColors.primaryNavy,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      '${household.number}',
                      style: AppTypography.label(
                        color: AppColors.textWhite,
                        fontSize: 12.5.sp,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                SizedBox(width: 10.w),

                // Home Icon Container
                Container(
                  width: 34.r,
                  height: 34.r,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8EFF7),
                    borderRadius: BorderRadius.circular(8.r),
                  ),
                  child: Icon(
                    Icons.home_rounded,
                    size: 18.r,
                    color: AppColors.primaryNavy.withValues(alpha: 0.8),
                  ),
                ),
                SizedBox(width: 12.w),

                // Name & Address
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        household.residentName,
                        style: AppTypography.heading(
                          color: AppColors.textPrimary,
                          fontSize: 14.sp,
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      SizedBox(height: 2.h),
                      Text(
                        household.address,
                        style: AppTypography.body(
                          color: AppColors.textSecondary,
                          fontSize: 12.sp,
                        ),
                      ),
                      Text(
                        household.cityStateZip,
                        style: AppTypography.body(
                          color: const Color(0xFF94A3B8),
                          fontSize: 11.sp,
                        ),
                      ),
                    ],
                  ),
                ),

                Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.textMuted,
                  size: 20.r,
                ),
              ],
            ),

            SizedBox(height: 12.h),

            // 3 Status Display Badges Row (Pray, Visited, Follow up)
            Row(
              children: [
                // Badge 1: Pray / Prayed Status
                Expanded(
                  child: Container(
                    height: 36.h,
                    decoration: BoxDecoration(
                      color: household.isPrayed
                          ? const Color(0xFFE8F5E9)
                          : AppColors.primaryNavy,
                      borderRadius: BorderRadius.circular(8.r),
                      border: Border.all(
                        color: household.isPrayed
                            ? const Color(0xFFC8E6C9)
                            : Colors.transparent,
                        width: 1.0,
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          household.isPrayed
                              ? Icons.check_rounded
                              : Icons.favorite_border_rounded,
                          size: 15.r,
                          color: household.isPrayed
                              ? const Color(0xFF2E7D32)
                              : Colors.white,
                        ),
                        SizedBox(width: 6.w),
                        Text(
                          household.isPrayed ? 'Prayed' : 'Pray',
                          style: AppTypography.label(
                            color: household.isPrayed
                                ? const Color(0xFF2E7D32)
                                : Colors.white,
                            fontSize: 12.sp,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                SizedBox(width: 8.w),

                // Badge 2: Visited Status
                Expanded(
                  child: Container(
                    height: 36.h,
                    decoration: BoxDecoration(
                      color: household.isVisited
                          ? const Color(0xFFE8F5E9)
                          : const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(8.r),
                      border: Border.all(
                        color: household.isVisited
                            ? const Color(0xFF2E7D32)
                            : const Color(0xFFE2E8F0),
                        width: 1.0,
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.place_outlined,
                          size: 15.r,
                          color: household.isVisited
                              ? const Color(0xFF2E7D32)
                              : const Color(0xFF64748B),
                        ),
                        SizedBox(width: 5.w),
                        Text(
                          'Visited',
                          style: AppTypography.label(
                            color: household.isVisited
                                ? const Color(0xFF2E7D32)
                                : const Color(0xFF64748B),
                            fontSize: 12.sp,
                            fontWeight: household.isVisited
                                ? FontWeight.w700
                                : FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                SizedBox(width: 8.w),

                // Badge 3: Follow up Status
                Expanded(
                  child: Container(
                    height: 36.h,
                    decoration: BoxDecoration(
                      color: household.hasFollowUp
                          ? const Color(0xFFFEF3C7)
                          : const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(8.r),
                      border: Border.all(
                        color: household.hasFollowUp
                            ? const Color(0xFFD97706)
                            : const Color(0xFFE2E8F0),
                        width: 1.0,
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.arrow_forward_rounded,
                          size: 14.r,
                          color: household.hasFollowUp
                              ? const Color(0xFFD97706)
                              : const Color(0xFF64748B),
                        ),
                        SizedBox(width: 5.w),
                        Text(
                          'Follow up',
                          style: AppTypography.label(
                            color: household.hasFollowUp
                                ? const Color(0xFFD97706)
                                : const Color(0xFF64748B),
                            fontSize: 12.sp,
                            fontWeight: household.hasFollowUp
                                ? FontWeight.w700
                                : FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
