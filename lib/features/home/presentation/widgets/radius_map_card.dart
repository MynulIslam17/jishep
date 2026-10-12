import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:gps_cielo/core/constants/app_colors.dart';
import 'package:gps_cielo/core/constants/app_typography.dart';
import 'package:gps_cielo/core/models/household_model.dart';

class RadiusMapCard extends StatelessWidget {
  const RadiusMapCard({
    required this.radiusHomes,
    required this.households,
    this.onTap,
    super.key,
  });

  final int radiusHomes;
  final List<HouseholdModel> households;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 180.h,
        width: double.infinity,
        decoration: BoxDecoration(
          color: const Color(0xFFE2EBF5),
          borderRadius: BorderRadius.circular(16.r),
          border: Border.all(color: AppColors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            // Map Grid Background Representation
            CustomPaint(size: Size.infinite, painter: _MapGridPainter()),

            // Concentric Radius Circle
            Center(
              child: Container(
                width: 140.r,
                height: 140.r,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.primaryNavy.withValues(alpha: 0.08),
                  border: Border.all(
                    color: AppColors.primaryNavy.withValues(alpha: 0.25),
                    width: 1.5,
                  ),
                ),
              ),
            ),

            // Center User Location Pin
            Center(
              child: Container(
                width: 16.r,
                height: 16.r,
                decoration: BoxDecoration(
                  color: AppColors.primaryNavy,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 3),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.2),
                      blurRadius: 6,
                    ),
                  ],
                ),
              ),
            ),

            // Household Marker Pins
            Positioned(
              top: 40.h,
              left: 80.w,
              child: _buildPin(Icons.location_on, AppColors.primaryNavy),
            ),
            Positioned(
              top: 50.h,
              right: 100.w,
              child: _buildPin(Icons.location_on, AppColors.primaryNavy),
            ),
            Positioned(
              bottom: 45.h,
              left: 120.w,
              child: _buildPin(Icons.location_on, AppColors.primaryGold),
            ),
            Positioned(
              bottom: 55.h,
              right: 80.w,
              child: _buildPin(Icons.location_on, AppColors.primaryNavy),
            ),
            Positioned(
              top: 90.h,
              right: 60.w,
              child: _buildPin(Icons.location_on, AppColors.primaryNavy),
            ),

            // Radius Badge Pill (Top Left)
            Positioned(
              top: 12.h,
              left: 12.w,
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 6.h),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(20.r),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 6,
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.radar_rounded,
                      size: 14.r,
                      color: AppColors.primaryNavy,
                    ),
                    SizedBox(width: 4.w),
                    Text(
                      'Radius: $radiusHomes homes',
                      style: AppTypography.label(
                        color: AppColors.textPrimary,
                        fontSize: 11.sp,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Zoom Controls (Bottom Right)
            Positioned(
              bottom: 12.h,
              right: 12.w,
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(8.r),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 6,
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    InkWell(
                      onTap: () {},
                      child: Padding(
                        padding: EdgeInsets.all(6.r),
                        child: Icon(
                          Icons.add,
                          size: 16.r,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    Container(height: 1, width: 24.w, color: AppColors.border),
                    InkWell(
                      onTap: () {},
                      child: Padding(
                        padding: EdgeInsets.all(6.r),
                        child: Icon(
                          Icons.remove,
                          size: 16.r,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPin(IconData icon, Color color) {
    return Icon(icon, size: 22.r, color: color);
  }
}

class _MapGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.6)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;

    // Draw stylized map road lines
    final path = Path();
    path.moveTo(0, size.height * 0.3);
    path.lineTo(size.width, size.height * 0.4);

    path.moveTo(size.width * 0.4, 0);
    path.lineTo(size.width * 0.35, size.height);

    path.moveTo(size.width * 0.7, 0);
    path.lineTo(size.width * 0.8, size.height);

    path.moveTo(0, size.height * 0.75);
    path.lineTo(size.width, size.height * 0.7);

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
