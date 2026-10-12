import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:gps_cielo/core/constants/app_colors.dart';
import 'package:gps_cielo/core/constants/app_typography.dart';
import 'package:gps_cielo/core/models/household_model.dart';
import 'package:gps_cielo/features/follow_up/presentation/controllers/follow_up_controller.dart';
import 'package:gps_cielo/shared/widgets/bottom_sheets/household_detail_bottom_sheet.dart';

class FollowUpHouseholdItem extends StatelessWidget {
  final HouseholdModel item;
  final FollowUpTab selectedTab;
  final ValueChanged<HouseholdModel> onUpdated;

  const FollowUpHouseholdItem({
    required this.item,
    required this.selectedTab,
    required this.onUpdated,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final showNotesAndEdit = item.hasFollowUp &&
        (selectedTab == FollowUpTab.followUp || selectedTab == FollowUpTab.all);

    return InkWell(
      onTap: () {
        HouseholdDetailBottomSheet.show(
          context,
          household: item,
          initialOpenNotes: item.hasFollowUp || selectedTab == FollowUpTab.followUp,
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
            // Top Row: Number Badge + Home Icon + Resident Info + Chevron
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
                      '${item.number}',
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

                // Resident Name & Status Badge & Address
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              item.residentName,
                              style: AppTypography.heading(
                                color: AppColors.textPrimary,
                                fontSize: 14.sp,
                                fontWeight: FontWeight.w700,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          SizedBox(width: 6.w),
                          _buildHouseholdStatusBadge(item),
                        ],
                      ),
                      SizedBox(height: 2.h),
                      Text(
                        item.address,
                        style: AppTypography.body(
                          color: AppColors.textSecondary,
                          fontSize: 12.sp,
                        ),
                      ),
                      Text(
                        item.cityStateZip,
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

            // Notes Block & Edit Button (Only for cards with follow-up status)
            if (showNotesAndEdit) ...[
              if (item.notes != null && item.notes!.trim().isNotEmpty) ...[
                SizedBox(height: 10.h),
                Padding(
                  padding: EdgeInsets.only(left: 42.w),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: RichText(
                          text: TextSpan(
                            children: [
                              TextSpan(
                                text: 'Notes: ',
                                style: TextStyle(
                                  color: const Color(0xFF1E293B),
                                  fontSize: 12.sp,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              TextSpan(
                                text: item.notes!,
                                style: TextStyle(
                                  color: const Color(0xFF64748B),
                                  fontSize: 12.sp,
                                  height: 1.35,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      SizedBox(width: 8.w),
                      // Edit Pencil Button (Opens Bottom Sheet directly in Note Edit Mode)
                      GestureDetector(
                        onTap: () {
                          HouseholdDetailBottomSheet.show(
                            context,
                            household: item,
                            initialOpenNotes: true,
                            onUpdated: onUpdated,
                          );
                        },
                        child: Container(
                          width: 28.r,
                          height: 28.r,
                          decoration: const BoxDecoration(
                            color: Color(0xFFF1F5F9),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.edit_outlined,
                            size: 14.r,
                            color: const Color(0xFF64748B),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              // Follow-up Date Row
              if (item.followUpDate != null && item.followUpDate!.isNotEmpty) ...[
                SizedBox(height: 6.h),
                Padding(
                  padding: EdgeInsets.only(left: 42.w),
                  child: Row(
                    children: [
                      Container(
                        width: 14.r,
                        height: 14.r,
                        decoration: const BoxDecoration(
                          color: Color(0xFFFEF3C7),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.schedule_rounded,
                          size: 9.r,
                          color: const Color(0xFFD97706),
                        ),
                      ),
                      SizedBox(width: 5.w),
                      Text(
                        'Follow up: ${item.followUpDate}',
                        style: TextStyle(
                          color: const Color(0xFFD97706),
                          fontSize: 11.5.sp,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildHouseholdStatusBadge(HouseholdModel item) {
    if (item.hasFollowUp) {
      return Container(
        padding: EdgeInsets.symmetric(horizontal: 7.w, vertical: 2.h),
        decoration: BoxDecoration(
          color: const Color(0xFFFEF3C7),
          borderRadius: BorderRadius.circular(6.r),
          border: Border.all(color: const Color(0xFFFCD34D), width: 0.8),
        ),
        child: Text(
          'Follow Up',
          style: TextStyle(
            color: const Color(0xFFB45309),
            fontSize: 10.5.sp,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
    }
    if (item.isVisited) {
      return Container(
        padding: EdgeInsets.symmetric(horizontal: 7.w, vertical: 2.h),
        decoration: BoxDecoration(
          color: const Color(0xFFE8F5E9),
          borderRadius: BorderRadius.circular(6.r),
          border: Border.all(color: const Color(0xFFA5D6A7), width: 0.8),
        ),
        child: Text(
          'Visited',
          style: TextStyle(
            color: const Color(0xFF2E7D32),
            fontSize: 10.5.sp,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
    }
    if (item.isPrayed) {
      return Container(
        padding: EdgeInsets.symmetric(horizontal: 7.w, vertical: 2.h),
        decoration: BoxDecoration(
          color: const Color(0xFFE8F5E9),
          borderRadius: BorderRadius.circular(6.r),
          border: Border.all(color: const Color(0xFFA5D6A7), width: 0.8),
        ),
        child: Text(
          'Prayed',
          style: TextStyle(
            color: const Color(0xFF2E7D32),
            fontSize: 10.5.sp,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
    }
    return const SizedBox.shrink();
  }
}
