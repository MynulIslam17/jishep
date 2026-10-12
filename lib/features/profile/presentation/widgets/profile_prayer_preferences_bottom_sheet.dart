import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:gps_cielo/core/constants/app_colors.dart';
import 'package:gps_cielo/core/constants/app_typography.dart';
import 'package:gps_cielo/shared/widgets/buttons/app_primary_button.dart';

class ProfilePrayerPreferencesBottomSheet extends StatelessWidget {
  final int initialTarget;
  final ValueChanged<int> onSavePreferences;

  const ProfilePrayerPreferencesBottomSheet({
    required this.initialTarget,
    required this.onSavePreferences,
    super.key,
  });

  static void show(
    BuildContext context, {
    required int initialTarget,
    required ValueChanged<int> onSavePreferences,
  }) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => ProfilePrayerPreferencesBottomSheet(
        initialTarget: initialTarget,
        onSavePreferences: onSavePreferences,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final targets = [3, 5, 10, 15];
    final selectedTargetRx = initialTarget.obs;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24.r)),
      ),
      padding: EdgeInsets.fromLTRB(20.w, 12.h, 20.w, 28.h),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildModalHandle(),
          SizedBox(height: 12.h),
          _buildModalHeader(context, title: 'Prayer Preferences'),
          SizedBox(height: 12.h),
          const Divider(color: AppColors.border, height: 1),
          SizedBox(height: 16.h),

          Text(
            'How many households would you like to pray for each day?',
            style: TextStyle(
              color: const Color(0xFF64748B),
              fontSize: 13.sp,
              height: 1.35,
            ),
          ),
          SizedBox(height: 16.h),

          Obx(
            () => Column(
              children: targets.map((target) {
                final isSelected = selectedTargetRx.value == target;
                return GestureDetector(
                  onTap: () => selectedTargetRx.value = target,
                  child: Container(
                    margin: EdgeInsets.only(bottom: 10.h),
                    padding: EdgeInsets.symmetric(
                      horizontal: 16.w,
                      vertical: 14.h,
                    ),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? const Color(0xFFF1F5F9)
                          : Colors.white,
                      borderRadius: BorderRadius.circular(12.r),
                      border: Border.all(
                        color: isSelected
                            ? AppColors.primaryNavy
                            : const Color(0xFFE2E8F0),
                        width: isSelected ? 1.5 : 1.0,
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '$target households / day',
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 14.sp,
                            fontWeight: isSelected
                                ? FontWeight.w700
                                : FontWeight.w500,
                          ),
                        ),
                        if (isSelected)
                          Container(
                            width: 22.r,
                            height: 22.r,
                            decoration: const BoxDecoration(
                              color: AppColors.primaryNavy,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.check_rounded,
                              size: 14.r,
                              color: Colors.white,
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),

          SizedBox(height: 20.h),

          AppPrimaryButton(
            label: 'Save Preferences',
            onPressed: () {
              onSavePreferences(selectedTargetRx.value);
              Navigator.of(context).pop();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildModalHandle() {
    return Center(
      child: Container(
        width: 40.w,
        height: 4.h,
        decoration: BoxDecoration(
          color: const Color(0xFFCBD5E1),
          borderRadius: BorderRadius.circular(2.r),
        ),
      ),
    );
  }

  Widget _buildModalHeader(BuildContext context, {required String title}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: AppTypography.heading(
            color: AppColors.primaryNavy,
            fontSize: 18.sp,
            fontWeight: FontWeight.w800,
          ),
        ),
        GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          child: Container(
            width: 32.r,
            height: 32.r,
            decoration: const BoxDecoration(
              color: Color(0xFFF1F5F9),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.close_rounded,
              size: 18.r,
              color: const Color(0xFF64748B),
            ),
          ),
        ),
      ],
    );
  }
}
