import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:gps_cielo/core/constants/app_colors.dart';
import 'package:gps_cielo/core/constants/app_typography.dart';
import 'package:gps_cielo/core/services/location_service.dart';
import 'package:gps_cielo/shared/widgets/buttons/app_primary_button.dart';
import 'package:gps_cielo/shared/widgets/inputs/address_autocomplete.dart';

/// Called with the typed address and, when picked from suggestions, its
/// coordinates.
typedef SaveAddressCallback =
    void Function(String address, ResolvedLocation? location);

class ProfileAddressBottomSheet extends StatefulWidget {
  final String currentAddress;
  final SaveAddressCallback onSaveAddress;
  final double? nearLatitude;
  final double? nearLongitude;

  const ProfileAddressBottomSheet({
    required this.currentAddress,
    required this.onSaveAddress,
    this.nearLatitude,
    this.nearLongitude,
    super.key,
  });

  static void show(
    BuildContext context, {
    required String currentAddress,
    required SaveAddressCallback onSaveAddress,
    double? nearLatitude,
    double? nearLongitude,
  }) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => ProfileAddressBottomSheet(
        currentAddress: currentAddress,
        onSaveAddress: onSaveAddress,
        nearLatitude: nearLatitude,
        nearLongitude: nearLongitude,
      ),
    );
  }

  @override
  State<ProfileAddressBottomSheet> createState() =>
      _ProfileAddressBottomSheetState();
}

class _ProfileAddressBottomSheetState extends State<ProfileAddressBottomSheet> {
  final addressController = TextEditingController();
  ResolvedLocation? _selectedLocation;

  @override
  void dispose() {
    addressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24.r)),
        ),
        padding: EdgeInsets.fromLTRB(20.w, 12.h, 20.w, 28.h),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildModalHandle(),
            SizedBox(height: 12.h),
            _buildModalHeader(context, title: 'My Address'),
            SizedBox(height: 12.h),
            const Divider(color: AppColors.border, height: 1),
            SizedBox(height: 16.h),

            Text(
              'CURRENT ADDRESS',
              style: TextStyle(
                color: const Color(0xFF64748B),
                fontSize: 11.sp,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
              ),
            ),
            SizedBox(height: 8.h),
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(14.r),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12.r),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Text(
                widget.currentAddress.isEmpty
                    ? 'Not set'
                    : widget.currentAddress,
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 13.5.sp,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),

            SizedBox(height: 18.h),

            Text(
              'UPDATE ADDRESS',
              style: TextStyle(
                color: const Color(0xFF64748B),
                fontSize: 11.sp,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
              ),
            ),
            SizedBox(height: 8.h),
            AddressAutocomplete(
              controller: addressController,
              openUp: true,
              nearLatitude: widget.nearLatitude,
              nearLongitude: widget.nearLongitude,
              onSelected: (suggestion) =>
                  _selectedLocation = suggestion.toResolvedLocation(),
              fieldBuilder: (context, fieldController, focusNode) => Container(
                height: 48.h,
                padding: EdgeInsets.symmetric(horizontal: 14.w),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(12.r),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.location_on_outlined,
                      size: 18.r,
                      color: const Color(0xFF94A3B8),
                    ),
                    SizedBox(width: 10.w),
                    Expanded(
                      child: TextField(
                        controller: fieldController,
                        focusNode: focusNode,
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 13.5.sp,
                        ),
                        decoration: const InputDecoration(
                          hintText: 'Enter new address...',
                          hintStyle: TextStyle(color: Color(0xFF94A3B8)),
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            SizedBox(height: 24.h),

            AppPrimaryButton(
              label: 'Save Address',
              onPressed: () {
                final text = addressController.text.trim();
                if (text.isNotEmpty) {
                  final selected = _selectedLocation;
                  widget.onSaveAddress(
                    text,
                    selected != null && selected.address == text
                        ? selected
                        : null,
                  );
                }
                Navigator.of(context).pop();
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModalHandle() {
    return Center(
      child: Container(
        width: 40.w,
        height: 4.h,
        decoration: BoxDecoration(
          color: const Color(0xFFCBD5E1),
          borderRadius: BorderRadius.circular(2.r),
        ),
      ),
    );
  }

  Widget _buildModalHeader(BuildContext context, {required String title}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: AppTypography.heading(
            color: AppColors.primaryNavy,
            fontSize: 18.sp,
            fontWeight: FontWeight.w800,
          ),
        ),
        GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          child: Container(
            width: 32.r,
            height: 32.r,
            decoration: const BoxDecoration(
              color: Color(0xFFF1F5F9),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.close_rounded,
              size: 18.r,
              color: const Color(0xFF64748B),
            ),
          ),
        ),
      ],
    );
  }
}
