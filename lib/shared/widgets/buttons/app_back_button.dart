import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:gps_cielo/core/constants/app_colors.dart';

/// Clean Circular/Round Shape Back Button
class AppBackButton extends StatelessWidget {
  const AppBackButton({
    this.onPressed,
    this.color = AppColors.textWhite,
    this.backgroundColor,
    this.size = 40,
    super.key,
  });

  final VoidCallback? onPressed;
  final Color color;
  final Color? backgroundColor;
  final double size;

  @override
  Widget build(BuildContext context) {
    final effectiveBgColor = backgroundColor ??
        (color == AppColors.textWhite
            ? Colors.white.withValues(alpha: 0.15)
            : AppColors.primaryNavy.withValues(alpha: 0.08));

    final effectiveBorderColor = color == AppColors.textWhite
        ? Colors.white.withValues(alpha: 0.25)
        : AppColors.primaryNavy.withValues(alpha: 0.15);

    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onPressed ?? () => Get.back(),
        customBorder: const CircleBorder(),
        child: Container(
          width: size.r,
          height: size.r,
          decoration: BoxDecoration(
            color: effectiveBgColor,
            shape: BoxShape.circle,
            border: Border.all(
              color: effectiveBorderColor,
              width: 1.2,
            ),
          ),
          child: Center(
            child: Padding(
              padding: EdgeInsets.only(right: 2.w),
              child: Icon(
                Icons.arrow_back_ios_new_rounded,
                size: (size * 0.42).r,
                color: color,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
