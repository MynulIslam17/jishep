import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:gps_cielo/core/constants/app_colors.dart';
import 'package:gps_cielo/core/constants/app_typography.dart';
import 'package:gps_cielo/core/models/household_model.dart';
import 'package:gps_cielo/shared/widgets/bottom_sheets/household_detail_bottom_sheet.dart';

class NeighborhoodHouseholdCard extends StatelessWidget {
  final HouseholdModel household;
  final VoidCallback onPrayToggle;
  final ValueChanged<HouseholdModel> onUpdated;

  const NeighborhoodHouseholdCard({
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
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
        child: Row(
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
            SizedBox(width: 12.w),

            // Resident Info
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

            // Status Indicator Green Dot
            if (household.isPrayed) ...[
              Container(
                width: 8.r,
                height: 8.r,
                decoration: const BoxDecoration(
                  color: Color(0xFF2E7D32),
                  shape: BoxShape.circle,
                ),
              ),
              SizedBox(width: 12.w),
            ],

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
