import 'dart:math' as math;
import 'package:flutter/material.dart';

class NeighborhoodMapPainter extends CustomPainter {
  final int radiusHomes;

  NeighborhoodMapPainter({required this.radiusHomes});

  @override
  void paint(Canvas canvas, Size size) {
    final blockPaint = Paint()
      ..color = const Color(0xFFE2E8F0).withValues(alpha: 0.75)
      ..style = PaintingStyle.fill;

    final roadPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 7.0
      ..style = PaintingStyle.stroke;

    const double stepX = 52.0;
    const double stepY = 38.0;

    for (double x = 4.0; x < size.width; x += stepX) {
      for (double y = 4.0; y < size.height; y += stepY) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(x, y, stepX - 6, stepY - 6),
            const Radius.circular(3),
          ),
          blockPaint,
        );
      }
    }

    for (double x = stepX / 2; x < size.width; x += stepX) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), roadPaint);
    }
    for (double y = stepY / 2; y < size.height; y += stepY) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), roadPaint);
    }

    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) * 0.38;

    final fillPaint = Paint()
      ..color = const Color(0xFF1B2A4A).withValues(alpha: 0.08)
      ..style = PaintingStyle.fill;

    final circleBorderPaint = Paint()
      ..color = const Color(0xFF1B2A4A).withValues(alpha: 0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;

    canvas.drawCircle(center, radius, fillPaint);
    canvas.drawCircle(center, radius, circleBorderPaint);
  }

  @override
  bool shouldRepaint(covariant NeighborhoodMapPainter oldDelegate) =>
      oldDelegate.radiusHomes != radiusHomes;
}
