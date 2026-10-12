import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:gps_cielo/core/constants/app_colors.dart';
import 'package:gps_cielo/core/constants/app_typography.dart';
import 'package:gps_cielo/core/models/household_model.dart';

class HouseholdCard extends StatelessWidget {
  const HouseholdCard({
    required this.household,
    required this.onPrayToggle,
    this.onTap,
    super.key,
  });

  final HouseholdModel household;
  final VoidCallback onPrayToggle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
        child: Row(
          children: [
            // Number Circle
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
                    fontSize: 13.sp,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),

            SizedBox(width: 10.w),

            // Home Icon
            Container(
              width: 38.r,
              height: 38.r,
              decoration: BoxDecoration(
                color: const Color(0xFFE8EFF7),
                borderRadius: BorderRadius.circular(10.r),
              ),
              child: Icon(
                Icons.home_rounded,
                size: 20.r,
                color: AppColors.primaryNavy.withValues(alpha: 0.8),
              ),
            ),

            SizedBox(width: 12.w),

            // Name and Address
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
                      color: AppColors.textSecondary,
                      fontSize: 11.sp,
                    ),
                  ),
                ],
              ),
            ),

            SizedBox(width: 8.w),

            // Pray / Prayed Action Button
            GestureDetector(
              onTap: onPrayToggle,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 8.h),
                decoration: BoxDecoration(
                  color: household.isPrayed
                      ? AppColors.successLight
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(20.r),
                  border: Border.all(
                    color: household.isPrayed
                        ? AppColors.successLight
                        : AppColors.primaryNavy,
                    width: 1.2,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      household.isPrayed
                          ? Icons.check_rounded
                          : Icons.favorite_border_rounded,
                      size: 15.r,
                      color: household.isPrayed
                          ? AppColors.success
                          : AppColors.primaryNavy,
                    ),
                    SizedBox(width: 5.w),
                    Text(
                      household.isPrayed ? 'Prayed' : 'Pray',
                      style: AppTypography.label(
                        color: household.isPrayed
                            ? AppColors.success
                            : AppColors.primaryNavy,
                        fontSize: 12.sp,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            SizedBox(width: 6.w),

            // Chevron
            Icon(
              Icons.chevron_right_rounded,
              color: AppColors.textMuted,
              size: 20.r,
            ),
          ],
        ),
      ),
    );
  }
}
