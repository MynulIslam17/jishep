import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:gps_cielo/core/constants/app_assets.dart';
import 'package:gps_cielo/core/constants/app_colors.dart';
import 'package:gps_cielo/core/constants/app_typography.dart';
import 'package:gps_cielo/core/utils/app_system_insets.dart';

class AppAuthHeader extends StatelessWidget {
  const AppAuthHeader({
    required this.title,
    required this.subtitle,
    super.key,
  });

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final topInset = AppSystemInsets.top(context);

    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(24.w, topInset + 20.h, 24.w, 28.h),
      decoration: BoxDecoration(
        color: AppColors.primaryNavy,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(28.r)),
      ),
      child: Column(
        children: [
          // Authentic logo_mark.svg with its original colors (no colorFilter tinting)
          SvgPicture.asset(
            AppAssets.logoMark,
            width: 52.w,
            height: 62.h,
            fit: BoxFit.contain,
          ),
          SizedBox(height: 16.h),
          Text(
            title,
            textAlign: TextAlign.center,
            style: AppTypography.heading(
              color: AppColors.textWhite,
              fontSize: 24.sp,
              fontWeight: FontWeight.w700,
            ),
          ),
          SizedBox(height: 4.h),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: AppTypography.body(
              color: AppColors.textWhite.withValues(alpha: 0.75),
              fontSize: 14.sp,
            ),
          ),
        ],
      ),
    );
  }
}

class AppScreenHeader extends StatelessWidget {
  const AppScreenHeader({
    required this.title,
    this.subtitle,
    this.action,
    super.key,
  });

  final String title;
  final String? subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final topInset = AppSystemInsets.top(context);

    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(20.w, topInset + 12.h, 20.w, 16.h),
      color: AppColors.primaryNavy,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: AppTypography.heading(
                  color: AppColors.textWhite,
                  fontSize: 20.sp,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (subtitle != null && subtitle!.isNotEmpty) ...[
                SizedBox(height: 2.h),
                Text(
                  subtitle!,
                  style: AppTypography.body(
                    color: AppColors.textWhite.withValues(alpha: 0.75),
                    fontSize: 12.sp,
                  ),
                ),
              ],
            ],
          ),
          ?action,
        ],
      ),
    );
  }
}
