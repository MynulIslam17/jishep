import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:gps_cielo/core/constants/app_colors.dart';
import 'package:gps_cielo/core/constants/app_typography.dart';

class AuthHeaderWidget extends StatelessWidget {
  final String title;
  final String subtitle;

  const AuthHeaderWidget({
    required this.title,
    required this.subtitle,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: AppTypography.heading(
            color: AppColors.primaryNavy,
            fontSize: 24.sp,
            fontWeight: FontWeight.w800,
          ),
        ),
        SizedBox(height: 6.h),
        Text(
          subtitle,
          style: AppTypography.body(
            color: AppColors.textSecondary,
            fontSize: 13.5.sp,
          ),
        ),
      ],
    );
  }
}
