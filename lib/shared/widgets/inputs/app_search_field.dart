import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:gps_cielo/core/constants/app_colors.dart';
import 'package:gps_cielo/core/constants/app_typography.dart';
import 'package:gps_cielo/core/services/address_suggestion_service.dart';
import 'package:gps_cielo/shared/widgets/inputs/address_autocomplete.dart';

class AppSearchField extends StatelessWidget {
  const AppSearchField({
    required this.controller,
    this.hint = '123 Main St, Hackensack, NJ 07601',
    this.onChanged,
    this.onSubmitted,
    this.onGpsPressed,
    this.onClear,
    this.onAddressSelected,
    this.nearLatitude,
    this.nearLongitude,
    super.key,
  });

  final TextEditingController controller;
  final String hint;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onGpsPressed;
  final VoidCallback? onClear;

  /// When set, address suggestions are shown while typing.
  final ValueChanged<AddressSuggestion>? onAddressSelected;
  final double? nearLatitude;
  final double? nearLongitude;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: onAddressSelected == null
              ? _buildField(controller, null)
              : AddressAutocomplete(
                  controller: controller,
                  nearLatitude: nearLatitude,
                  nearLongitude: nearLongitude,
                  onSelected: onAddressSelected!,
                  fieldBuilder: (context, fieldController, focusNode) =>
                      _buildField(fieldController, focusNode),
                ),
        ),
        if (onGpsPressed != null) ...[
          SizedBox(width: 8.w),
          Container(
            height: 48.h,
            width: 48.h,
            decoration: BoxDecoration(
              color: AppColors.inputSurface,
              borderRadius: BorderRadius.circular(12.r),
              border: Border.all(color: AppColors.border),
            ),
            child: IconButton(
              icon: Icon(
                Icons.my_location_rounded,
                size: 20.r,
                color: AppColors.primaryNavy,
              ),
              onPressed: onGpsPressed,
              tooltip: 'Current location',
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildField(
    TextEditingController fieldController,
    FocusNode? focusNode,
  ) {
    return Container(
      height: 48.h,
      decoration: BoxDecoration(
        color: AppColors.inputSurface,
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(color: AppColors.border),
      ),
      child: TextField(
        controller: fieldController,
        focusNode: focusNode,
        onChanged: onChanged,
        onSubmitted: onSubmitted,
        style: AppTypography.style(
          color: AppColors.textPrimary,
          fontSize: 14.sp,
        ),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: AppTypography.style(
            color: AppColors.textSecondary,
            fontSize: 14.sp,
          ),
          border: InputBorder.none,
          contentPadding: EdgeInsets.symmetric(
            horizontal: 16.w,
            vertical: 12.h,
          ),
          suffixIcon: ListenableBuilder(
            listenable: fieldController,
            builder: (context, _) {
              if (fieldController.text.isEmpty) return const SizedBox.shrink();
              return IconButton(
                icon: Icon(
                  Icons.close_rounded,
                  size: 18.r,
                  color: AppColors.textSecondary,
                ),
                onPressed: () {
                  fieldController.clear();
                  onClear?.call();
                },
              );
            },
          ),
        ),
      ),
    );
  }
}
