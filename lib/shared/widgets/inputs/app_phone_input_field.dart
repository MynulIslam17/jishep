import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:gps_cielo/core/constants/app_colors.dart';
import 'package:gps_cielo/core/constants/app_typography.dart';
import 'package:intl_phone_field/countries.dart';
import 'package:intl_phone_field/country_picker_dialog.dart';
import 'package:intl_phone_field/intl_phone_field.dart';
import 'package:intl_phone_field/phone_number.dart';

class AppPhoneInputField extends StatelessWidget {
  final String label;
  final String hint;
  final TextEditingController? controller;

  /// ISO country code shown first. Defaults to the device's region.
  final String? initialCountryCode;
  final ValueChanged<PhoneNumber>? onChanged;
  final bool isRequired;
  final FocusNode? focusNode;
  final bool showDropdownIcon;
  final TextInputAction textInputAction;

  const AppPhoneInputField({
    super.key,
    this.label = 'Phone Number',
    this.hint = 'Enter phone number',
    this.controller,
    this.initialCountryCode,
    this.onChanged,
    this.isRequired = false,
    this.focusNode,
    this.showDropdownIcon = true,
    this.textInputAction = TextInputAction.next,
  });

  @override
  Widget build(BuildContext context) {
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
        IntlPhoneField(
          controller: controller,
          focusNode: focusNode,
          initialCountryCode: initialCountryCode ?? _deviceCountryCode(),
          showDropdownIcon: showDropdownIcon,
          dropdownIconPosition: IconPosition.trailing,
          dropdownIcon: const Icon(
            Icons.arrow_drop_down_rounded,
            color: AppColors.textSecondary,
          ),
          flagsButtonPadding: EdgeInsets.symmetric(horizontal: 10.w),
          style: AppTypography.style(
            color: AppColors.textPrimary,
            fontSize: 14.sp,
          ),
          cursorColor: AppColors.primaryNavy,
          textInputAction: textInputAction,
          pickerDialogStyle: PickerDialogStyle(
            backgroundColor: AppColors.surface,
            countryCodeStyle: AppTypography.style(
              color: AppColors.primaryNavy,
              fontSize: 14.sp,
              fontWeight: FontWeight.w600,
            ),
            countryNameStyle: AppTypography.style(
              color: AppColors.textPrimary,
              fontSize: 14.sp,
            ),
            searchFieldInputDecoration: InputDecoration(
              hintText: 'Search country...',
              hintStyle: AppTypography.style(
                color: AppColors.textMuted,
                fontSize: 14.sp,
              ),
              filled: true,
              fillColor: AppColors.inputSurface,
              prefixIcon: const Icon(
                Icons.search,
                color: AppColors.textSecondary,
              ),
              contentPadding: EdgeInsets.symmetric(
                horizontal: 14.w,
                vertical: 12.h,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10.r),
                borderSide: const BorderSide(color: AppColors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10.r),
                borderSide: const BorderSide(color: AppColors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10.r),
                borderSide: const BorderSide(
                  color: AppColors.primaryNavy,
                  width: 1.5,
                ),
              ),
            ),
          ),
          decoration: InputDecoration(
            isDense: true,
            hintText: hint,
            hintStyle: AppTypography.style(
              color: AppColors.textMuted,
              fontSize: 14.sp,
            ),
            filled: true,
            fillColor: AppColors.inputSurface,
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
              borderSide: const BorderSide(
                color: AppColors.primaryNavy,
                width: 1.5,
              ),
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
          onChanged: (phone) => onChanged?.call(_normalized(phone)),
          // The package does not report a new country for an already typed
          // number, which would keep the old dial code.
          onCountryChanged: (Country country) => onChanged?.call(
            _normalized(
              PhoneNumber(
                countryISOCode: country.code,
                countryCode: '+${country.dialCode}${country.regionCode}',
                number: controller?.text ?? '',
              ),
            ),
          ),
        ),
      ],
    );
  }

  static String _deviceCountryCode() {
    final code = WidgetsBinding.instance.platformDispatcher.locale.countryCode;
    final known = code != null && countries.any((c) => c.code == code);
    return known ? code : 'US';
  }

  /// Removes spaces/dashes and a national trunk "0" (e.g. 01792… -> 1792…)
  /// so `completeNumber` is valid E.164 for Firebase.
  static PhoneNumber _normalized(PhoneNumber phone) {
    var digits = phone.number.replaceAll(RegExp(r'\D'), '');
    if (phone.countryISOCode != 'IT') {
      digits = digits.replaceFirst(RegExp(r'^0+'), '');
    }
    return PhoneNumber(
      countryISOCode: phone.countryISOCode,
      countryCode: phone.countryCode,
      number: digits,
    );
  }
}
