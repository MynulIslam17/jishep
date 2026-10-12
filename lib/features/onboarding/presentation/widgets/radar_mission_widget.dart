import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:gps_cielo/core/constants/app_colors.dart';

/// Interactive Radar Mission Widget with Clockwise Rotating Household Dots
class RadarMissionWidget extends StatefulWidget {
  const RadarMissionWidget({this.size = 240, super.key});

  final double size;

  @override
  State<RadarMissionWidget> createState() => _RadarMissionWidgetState();
}

class _RadarMissionWidgetState extends State<RadarMissionWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _rotationController;

  @override
  void initState() {
    super.initState();
    _rotationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 16),
    )..repeat();
  }

  @override
  void dispose() {
    _rotationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size.r;

    return SizedBox(
      width: s,
      height: s,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // 1. Subtle light circular disc background
          Container(
            width: s,
            height: s,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Color(0xFFEFF3F8),
            ),
          ),

          // 2. Inner dashed gold ring
          CustomPaint(
            size: Size(s * 0.55, s * 0.55),
            painter: _DashedCirclePainter(
              color: AppColors.primaryGold.withValues(alpha: 0.7),
              dashWidth: 4,
              dashSpace: 4,
            ),
          ),

          // 3. Clockwise Rotating Layer (Outer Dashed Ring + 8 Household Dots)
          RotationTransition(
            turns: _rotationController,
            child: SizedBox(
              width: s,
              height: s,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Outer dashed ring
                  CustomPaint(
                    size: Size(s * 0.85, s * 0.85),
                    painter: _DashedCirclePainter(
                      color: const Color(0xFFCBD5E1),
                      dashWidth: 4,
                      dashSpace: 4,
                    ),
                  ),

                  // 8 Radially distributed household nodes
                  ...List.generate(8, (index) {
                    final angle = (index * (2 * math.pi / 8)) - (math.pi / 2);
                    final radius = (s * 0.425);
                    final x = radius * math.cos(angle);
                    final y = radius * math.sin(angle);

                    return Transform.translate(
                      offset: Offset(x, y),
                      child: Container(
                        width: 14.r,
                        height: 14.r,
                        decoration: BoxDecoration(
                          color: const Color(0xFF8B9CB3),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.12),
                              blurRadius: 3,
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),

          // 4. Center Gold Badge with White House Icon
          Container(
            width: s * 0.30,
            height: s * 0.30,
            decoration: BoxDecoration(
              color: AppColors.primaryGold,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: AppColors.primaryGold.withValues(alpha: 0.3),
                  blurRadius: 12,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Icon(
              Icons.home_rounded,
              color: Colors.white,
              size: (s * 0.18),
            ),
          ),
        ],
      ),
    );
  }
}

class _DashedCirclePainter extends CustomPainter {
  final Color color;
  final double dashWidth;
  final double dashSpace;

  _DashedCirclePainter({
    required this.color,
    this.dashWidth = 4,
    this.dashSpace = 4,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    final radius = size.width / 2;
    final circumference = 2 * math.pi * radius;
    final totalDashLength = dashWidth + dashSpace;
    final dashCount = (circumference / totalDashLength).floor();
    final adjustedDashAngle = (2 * math.pi) / dashCount;
    final dashSweep = adjustedDashAngle * (dashWidth / totalDashLength);

    for (int i = 0; i < dashCount; i++) {
      final startAngle = i * adjustedDashAngle;
      canvas.drawArc(
        Rect.fromCircle(center: Offset(size.width / 2, size.height / 2), radius: radius),
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
