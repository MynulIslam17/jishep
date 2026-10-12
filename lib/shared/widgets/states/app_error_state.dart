import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:gps_cielo/core/constants/app_colors.dart';
import 'package:gps_cielo/core/constants/app_typography.dart';
import 'package:gps_cielo/shared/widgets/buttons/app_primary_button.dart';

class AppErrorState extends StatelessWidget {
  const AppErrorState({
    required this.message,
    this.title = 'Oops! Something went wrong',
    this.onRetry,
    super.key,
  });

  final String title;
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(32.r),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72.r,
              height: 72.r,
              decoration: BoxDecoration(
                color: AppColors.dangerLight,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.error_outline_rounded, size: 36.r, color: AppColors.danger),
            ),
            SizedBox(height: 16.h),
            Text(
              title,
              textAlign: TextAlign.center,
              style: AppTypography.heading(
                color: AppColors.textPrimary,
                fontSize: 16.sp,
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(height: 6.h),
            Text(
              message,
              textAlign: TextAlign.center,
              style: AppTypography.body(
                color: AppColors.textSecondary,
                fontSize: 13.sp,
              ),
            ),
            if (onRetry != null) ...[
              SizedBox(height: 20.h),
              AppPrimaryButton(
                label: 'Try Again',
                onPressed: onRetry!,
                height: 42,
                fontSize: 13,
                icon: const Icon(Icons.refresh_rounded, size: 18, color: Colors.white),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
