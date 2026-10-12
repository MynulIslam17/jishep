import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:gps_cielo/core/constants/app_colors.dart';
import 'package:gps_cielo/core/constants/app_typography.dart';

class AppPrimaryButton extends StatelessWidget {
  const AppPrimaryButton({
    required this.label,
    required this.onPressed,
    this.isLoading = false,
    this.height = 52,
    this.borderRadius = 12,
    this.fontSize = 15,
    this.backgroundColor = AppColors.primaryNavy,
    this.textColor = AppColors.textWhite,
    this.icon,
    this.padding = EdgeInsets.zero,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;
  final double height;
  final double borderRadius;
  final double fontSize;
  final Color backgroundColor;
  final Color textColor;
  final Widget? icon;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: SizedBox(
        width: double.infinity,
        height: height.h,
        child: ElevatedButton(
          onPressed: isLoading ? null : onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: backgroundColor,
            foregroundColor: textColor,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(borderRadius.r),
            ),
            padding: EdgeInsets.symmetric(horizontal: 16.w),
          ),
          child: isLoading
              ? SizedBox.square(
                  dimension: 20.r,
                  child: CircularProgressIndicator(
                    color: textColor,
                    strokeWidth: 2.2,
                  ),
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (icon != null) ...[
                      icon!,
                      SizedBox(width: 8.w),
                    ],
                    Text(
                      label,
                      style: AppTypography.heading(
                        color: textColor,
                        fontSize: fontSize.sp,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
