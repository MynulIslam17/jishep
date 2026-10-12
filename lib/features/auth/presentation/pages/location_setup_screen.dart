import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:gps_cielo/core/constants/app_colors.dart';
import 'package:gps_cielo/core/constants/app_typography.dart';
import 'package:gps_cielo/core/utils/system_ui_config.dart';
import 'package:gps_cielo/features/auth/presentation/controllers/location_setup_controller.dart';
import 'package:gps_cielo/shared/widgets/buttons/app_primary_button.dart';
import 'package:gps_cielo/shared/widgets/inputs/address_autocomplete.dart';
import 'package:gps_cielo/shared/widgets/layout/app_header.dart';

class LocationSetupScreen extends GetView<LocationSetupController> {
  const LocationSetupScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiConfig.darkOverlay,
      child: Scaffold(
        backgroundColor: AppColors.surface,
        body: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Clean App Auth Header without any step indicators
              const AppAuthHeader(
                title: 'Where do you live?',
                subtitle: 'Set your home address to find nearby neighbors.',
              ),

              // Interactive Form Body
              Padding(
                padding: EdgeInsets.fromLTRB(20.w, 24.h, 20.w, 28.h),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Your address label
                    Text(
                      'Your address',
                      style: AppTypography.label(
                        color: AppColors.primaryNavy,
                        fontSize: 14.sp,
                        fontWeight: FontWeight.w700,
                      ),
                    ),

                    SizedBox(height: 8.h),

                    // Address Input Field
                    AddressAutocomplete(
                      controller: controller.addressController,
                      onSelected: controller.selectSuggestion,
                      fieldBuilder: (context, fieldController, focusNode) =>
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12.r),
                              border: Border.all(
                                color: const Color(0xFF1B2A4A),
                                width: 1.2,
                              ),
                            ),
                            padding: EdgeInsets.symmetric(
                              horizontal: 14.w,
                              vertical: 4.h,
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.location_on_outlined,
                                  color: const Color(0xFF64748B),
                                  size: 20.r,
                                ),
                                SizedBox(width: 10.w),
                                Expanded(
                                  child: TextField(
                                    controller: fieldController,
                                    focusNode: focusNode,
                                    style: TextStyle(
                                      color: AppColors.primaryNavy,
                                      fontSize: 14.sp,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    decoration: const InputDecoration(
                                      hintText: 'Enter your street address',
                                      border: InputBorder.none,
                                      isDense: true,
                                      contentPadding: EdgeInsets.symmetric(
                                        vertical: 10,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                    ),

                    SizedBox(height: 12.h),

                    // Use my current location Button
                    Obx(
                      () => GestureDetector(
                        onTap: controller.isLocating.value
                            ? null
                            : controller.useCurrentLocation,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.my_location_rounded,
                              color: AppColors.primaryNavy,
                              size: 16.r,
                            ),
                            SizedBox(width: 6.w),
                            Text(
                              controller.isLocating.value
                                  ? 'Detecting GPS location...'
                                  : 'Use my current location',
                              style: AppTypography.label(
                                color: AppColors.primaryNavy,
                                fontSize: 13.sp,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    SizedBox(height: 20.h),

                    // Interactive Map Preview Card
                    _buildMapPreview(),

                    SizedBox(height: 22.h),

                    // Search Radius Slider Header
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Search radius',
                          style: AppTypography.label(
                            color: AppColors.primaryNavy,
                            fontSize: 14.sp,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Obx(
                          () => Text(
                            '${controller.radius.value.toInt()} homes',
                            style: AppTypography.heading(
                              color: AppColors.primaryNavy,
                              fontSize: 14.sp,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),

                    SizedBox(height: 6.h),

                    // Radius Slider
                    Obx(
                      () => SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 5.h,
                          activeTrackColor: AppColors.primaryNavy,
                          inactiveTrackColor: const Color(0xFFE2E8F0),
                          thumbColor: AppColors.primaryNavy,
                          thumbShape: RoundSliderThumbShape(
                            enabledThumbRadius: 9.r,
                          ),
                          overlayShape: RoundSliderOverlayShape(
                            overlayRadius: 18.r,
                          ),
                        ),
                        child: Slider(
                          value: controller.radius.value,
                          min: 5,
                          max: 25,
                          divisions: 4,
                          onChanged: controller.setRadius,
                        ),
                      ),
                    ),

                    // Scale labels
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 10.w),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('5 homes', style: _scaleTextStyle()),
                          Text('15 homes', style: _scaleTextStyle()),
                          Text('25 homes', style: _scaleTextStyle()),
                        ],
                      ),
                    ),

                    SizedBox(height: 20.h),

                    // Household Summary Card
                    Container(
                      padding: EdgeInsets.all(16.r),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(16.r),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 44.r,
                            height: 44.r,
                            decoration: BoxDecoration(
                              color: const Color(0xFFE2E8F0),
                              borderRadius: BorderRadius.circular(12.r),
                            ),
                            child: Icon(
                              Icons.home_rounded,
                              color: AppColors.primaryNavy,
                              size: 24.r,
                            ),
                          ),
                          SizedBox(width: 14.w),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Obx(
                                  () => Text(
                                    '~${(controller.radius.value * 2.4).round()} households found',
                                    style: AppTypography.heading(
                                      color: AppColors.primaryNavy,
                                      fontSize: 15.sp,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                                SizedBox(height: 2.h),
                                Obx(
                                  () => Text(
                                    'within a radius of ${controller.radius.value.toInt()} homes',
                                    style: AppTypography.body(
                                      color: const Color(0xFF64748B),
                                      fontSize: 12.sp,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    SizedBox(height: 24.h),

                    // Confirm and Continue CTA Button
                    Obx(
                      () => AppPrimaryButton(
                        label: 'Confirm and continue \u2192',
                        backgroundColor: AppColors.primaryNavy,
                        textColor: AppColors.textWhite,
                        isLoading: controller.isSubmitting.value,
                        onPressed: controller.confirmLocation,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMapPreview() {
    return Obx(() {
      final ringRadius = (50 + (controller.radius.value - 5) * 2.2).r;

      return Container(
        height: 180.h,
        width: double.infinity,
        decoration: BoxDecoration(
          color: const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(16.r),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // City Map Grid Lines
            CustomPaint(size: Size.infinite, painter: _CityGridPainter()),

            // Dashed Radius Circle
            CustomPaint(
              size: Size(ringRadius * 2, ringRadius * 2),
              painter: _MapRadiusPainter(
                color: AppColors.primaryNavy.withValues(alpha: 0.7),
              ),
            ),

            // Center Navy Pin
            Container(
              width: 32.r,
              height: 32.r,
              decoration: BoxDecoration(
                color: AppColors.primaryNavy,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.25),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Icon(
                Icons.location_on_rounded,
                color: Colors.white,
                size: 18.r,
              ),
            ),

            // Floating Address Pill at Bottom
            Positioned(
              bottom: 12.h,
              left: 16.w,
              right: 16.w,
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 8.h),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10.r),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Text(
                  controller.addressRx.value.isEmpty
                      ? 'Enter your address'
                      : controller.addressRx.value,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.primaryNavy,
                    fontSize: 12.sp,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    });
  }

  TextStyle _scaleTextStyle() {
    return TextStyle(
      color: const Color(0xFF94A3B8),
      fontSize: 11.sp,
      fontWeight: FontWeight.w500,
    );
  }
}

class _CityGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final blockPaint = Paint()
      ..color = const Color(0xFFE2E8F0).withValues(alpha: 0.7)
      ..style = PaintingStyle.fill;

    final roadPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 6.0
      ..style = PaintingStyle.stroke;

    // Draw city blocks
    const double stepX = 54.0;
    const double stepY = 40.0;

    for (double x = 8.0; x < size.width; x += stepX) {
      for (double y = 8.0; y < size.height; y += stepY) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(x, y, stepX - 8, stepY - 8),
            const Radius.circular(4),
          ),
          blockPaint,
        );
      }
    }

    // Draw main roads
    for (double x = stepX / 2; x < size.width; x += stepX) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), roadPaint);
    }
    for (double y = stepY / 2; y < size.height; y += stepY) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), roadPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _MapRadiusPainter extends CustomPainter {
  final Color color;

  _MapRadiusPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;

    final fillPaint = Paint()
      ..color = AppColors.primaryNavy.withValues(alpha: 0.05)
      ..style = PaintingStyle.fill;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    canvas.drawCircle(center, radius, fillPaint);

    const double dashWidth = 4.0;
    const double dashSpace = 4.0;
    final circumference = 2 * math.pi * radius;
    final count = (circumference / (dashWidth + dashSpace)).floor();
    final adjustedSweep = (2 * math.pi) / count;
    final dashSweep = adjustedSweep * (dashWidth / (dashWidth + dashSpace));

    for (int i = 0; i < count; i++) {
      final startAngle = i * adjustedSweep;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        dashSweep,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
