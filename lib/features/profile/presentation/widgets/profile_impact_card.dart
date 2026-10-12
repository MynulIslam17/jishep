import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:gps_cielo/core/constants/app_colors.dart';

class ProfileImpactCard extends StatelessWidget {
  final int homesPrayed;
  final int visitsMade;

  const ProfileImpactCard({
    required this.homesPrayed,
    required this.visitsMade,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(16.r),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'MY IMPACT',
            style: TextStyle(
              color: const Color(0xFF64748B),
              fontSize: 11.5.sp,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
            ),
          ),
          SizedBox(height: 12.h),
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: EdgeInsets.symmetric(vertical: 16.h),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12.r),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Column(
                    children: [
                      Text(
                        '$homesPrayed',
                        style: TextStyle(
                          color: AppColors.primaryNavy,
                          fontSize: 24.sp,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      SizedBox(height: 2.h),
                      Text(
                        'Homes Prayed',
                        style: TextStyle(
                          color: const Color(0xFF64748B),
                          fontSize: 11.5.sp,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(width: 12.w),
              Expanded(
                child: Container(
                  padding: EdgeInsets.symmetric(vertical: 16.h),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12.r),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Column(
                    children: [
                      Text(
                        '$visitsMade',
                        style: TextStyle(
                          color: AppColors.primaryNavy,
                          fontSize: 24.sp,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      SizedBox(height: 2.h),
                      Text(
                        'Visits Made',
                        style: TextStyle(
                          color: const Color(0xFF64748B),
                          fontSize: 11.5.sp,
                          fontWeight: FontWeight.w500,
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
    );
  }
}
