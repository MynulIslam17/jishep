import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:gps_cielo/core/constants/app_colors.dart';

/// "My impact": lifetime prayers (every round, from the prayer history),
/// distinct homes prayed for, and visits.
class ProfileImpactCard extends StatelessWidget {
  final int homesPrayed;
  final int visitsMade;

  /// Prayers over every round; a home prayed for in three rounds counts
  /// three times.
  final int prayersOffered;

  const ProfileImpactCard({
    required this.homesPrayed,
    required this.visitsMade,
    this.prayersOffered = 0,
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
              Expanded(child: _tile('$prayersOffered', 'Prayers')),
              SizedBox(width: 8.w),
              Expanded(child: _tile('$homesPrayed', 'Homes Prayed')),
              SizedBox(width: 8.w),
              Expanded(child: _tile('$visitsMade', 'Visits Made')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _tile(String value, String label) {
    return Container(
      padding: EdgeInsets.symmetric(vertical: 16.h, horizontal: 4.w),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: TextStyle(
                color: AppColors.primaryNavy,
                fontSize: 24.sp,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          SizedBox(height: 2.h),
          Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: const Color(0xFF64748B),
              fontSize: 11.5.sp,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
