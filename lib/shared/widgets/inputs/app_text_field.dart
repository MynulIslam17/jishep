import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:gps_cielo/core/constants/app_colors.dart';
import 'package:gps_cielo/core/constants/app_typography.dart';

class AppTextField extends StatelessWidget {
  const AppTextField({
    required this.label,
    required this.hint,
    required this.controller,
    this.prefixIcon,
    this.isPassword = false,
    this.isPasswordVisible = false,
    this.onPasswordVisibilityPressed,
    this.keyboardType,
    this.textInputAction,
    this.suffix,
    this.showClearButton = false,
    this.onChanged,
    this.validator,
    this.maxLines = 1,
    this.isRequired = false,
    this.readOnly = false,
    this.onTap,
    super.key,
  });

  final String label;
  final String hint;
  final TextEditingController controller;
  final Widget? prefixIcon;
  final bool isPassword;
  final bool isPasswordVisible;
  final VoidCallback? onPasswordVisibilityPressed;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final Widget? suffix;
  final bool showClearButton;
  final ValueChanged<String>? onChanged;
  final FormFieldValidator<String>? validator;
  final int maxLines;
  final bool isRequired;
  final bool readOnly;
  final VoidCallback? onTap;

  void _clear() {
    if (controller.text.isEmpty) return;
    controller.clear();
    onChanged?.call('');
  }

  Widget? _buildSuffixIcon() {
    if (isPassword) {
      return IconButton(
        onPressed: onPasswordVisibilityPressed,
        icon: Icon(
          isPasswordVisible ? Icons.visibility_outlined : Icons.visibility_off_outlined,
          color: AppColors.textSecondary,
          size: 20.r,
        ),
      );
    }
    if (suffix != null) return suffix;
    if (!showClearButton) return null;

    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        if (controller.text.isEmpty) return const SizedBox.shrink();
        return IconButton(
          onPressed: _clear,
          tooltip: 'Clear',
          icon: Icon(
            Icons.cancel_rounded,
            color: AppColors.textSecondary,
            size: 18.r,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final field = TextFormField(
      controller: controller,
      readOnly: readOnly || onTap != null,
      obscureText: isPassword && !isPasswordVisible,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      textAlignVertical: TextAlignVertical.center,
      onChanged: onChanged,
      validator: validator,
      maxLines: isPassword ? 1 : maxLines,
      style: AppTypography.style(
        color: AppColors.textPrimary,
        fontSize: 14.sp,
      ),
      cursorColor: AppColors.primaryNavy,
      decoration: InputDecoration(
        isDense: true,
        hintText: hint,
        hintStyle: AppTypography.style(
          color: AppColors.textMuted,
          fontSize: 14.sp,
        ),
        filled: true,
        fillColor: AppColors.inputSurface,
        prefixIcon: prefixIcon,
        prefixIconConstraints: BoxConstraints(
          minWidth: 44.w,
          minHeight: 48.h,
        ),
        suffixIcon: _buildSuffixIcon(),
        suffixIconConstraints: BoxConstraints(
          minWidth: 44.w,
          minHeight: 48.h,
        ),
        contentPadding: EdgeInsets.symmetric(
          horizontal: 16.w,
          vertical: 14.h,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12.r),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12.r),
          borderSide: const BorderSide(color: AppColors.primaryNavy, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12.r),
          borderSide: const BorderSide(color: AppColors.danger),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12.r),
          borderSide: const BorderSide(color: AppColors.danger, width: 1.5),
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label.isNotEmpty) ...[
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: AppTypography.heading(
                  color: AppColors.textPrimary,
                  fontSize: 14.sp,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (isRequired) ...[
                SizedBox(width: 4.w),
                Text(
                  '*',
                  style: TextStyle(
                    color: AppColors.danger,
                    fontSize: 14.sp,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ],
          ),
          SizedBox(height: 8.h),
        ],
        if (onTap != null)
          GestureDetector(
            onTap: onTap,
            behavior: HitTestBehavior.opaque,
            child: IgnorePointer(child: field),
          )
        else
          field,
      ],
    );
  }
}
