import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:gps_cielo/core/constants/app_colors.dart';
import 'package:gps_cielo/core/constants/app_typography.dart';

class NotificationEmptyState extends StatelessWidget {
  final String title;
  final String message;

  const NotificationEmptyState({
    this.title = 'No Notifications',
    this.message = 'You are all caught up! When you have prayer reminders or updates, they will appear here.',
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 32.w, vertical: 48.h),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72.r,
              height: 72.r,
              decoration: BoxDecoration(
                color: const Color(0xFFE8EFF7),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Icon(
                Icons.notifications_none_rounded,
                size: 38.r,
                color: AppColors.primaryNavy,
              ),
            ),
            SizedBox(height: 16.h),
            Text(
              title,
              style: AppTypography.heading(
                color: AppColors.primaryNavy,
                fontSize: 16.sp,
                fontWeight: FontWeight.w700,
              ),
            ),
            SizedBox(height: 6.h),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: const Color(0xFF64748B),
                fontSize: 13.sp,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
