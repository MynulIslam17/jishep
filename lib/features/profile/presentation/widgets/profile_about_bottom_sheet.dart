import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:gps_cielo/core/constants/app_colors.dart';
import 'package:gps_cielo/core/constants/app_typography.dart';

class ProfileAboutBottomSheet extends StatelessWidget {
  const ProfileAboutBottomSheet({super.key});

  static void show(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => const ProfileAboutBottomSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24.r)),
      ),
      padding: EdgeInsets.fromLTRB(20.w, 12.h, 20.w, 32.h),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _buildModalHandle(),
          SizedBox(height: 12.h),
          _buildModalHeader(context, title: 'About GPS PARA EL CIELO'),
          SizedBox(height: 12.h),
          const Divider(color: AppColors.border, height: 1),
          SizedBox(height: 20.h),

          // App Logo Container
          Container(
            width: 68.r,
            height: 68.r,
            decoration: BoxDecoration(
              color: AppColors.primaryNavy,
              borderRadius: BorderRadius.circular(18.r),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primaryNavy.withValues(alpha: 0.25),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Center(
              child: Icon(
                Icons.explore_rounded,
                size: 36.r,
                color: AppColors.primaryGold,
              ),
            ),
          ),

          SizedBox(height: 14.h),

          Text(
            'GPS PARA EL CIELO',
            style: AppTypography.heading(
              color: AppColors.primaryNavy,
              fontSize: 18.sp,
              fontWeight: FontWeight.w800,
            ),
          ),
          SizedBox(height: 4.h),
          Text(
            'Version 1.0.0 \u2022 Faith-based community outreach',
            style: TextStyle(color: const Color(0xFF64748B), fontSize: 12.sp),
          ),

          SizedBox(height: 16.h),

          Text(
            'GPS PARA EL CIELO helps believers pray for their neighbors systematically, building bridges between households and the local church.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 13.5.sp,
              height: 1.45,
            ),
          ),

          SizedBox(height: 20.h),

          Container(
            width: double.infinity,
            padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 12.h),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(12.r),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Center(
              child: Text(
                'Built with love for the community \u2022 Connecting homes to faith',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: const Color(0xFF64748B),
                  fontSize: 11.5.sp,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
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
