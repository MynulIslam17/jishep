import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:gps_cielo/core/constants/app_colors.dart';
import 'package:gps_cielo/core/constants/app_typography.dart';
import 'package:gps_cielo/core/services/location_service.dart';

/// Shows where a picked location came from and its coordinates, so the user
/// can check it before saving.
class SelectedLocationNote extends StatelessWidget {
  const SelectedLocationNote({required this.location, super.key});

  final ResolvedLocation? location;

  @override
  Widget build(BuildContext context) {
    final location = this.location;
    if (location == null) return const SizedBox.shrink();

    final String text;
    if (location.source == LocationSource.gps && !location.hasAddress) {
      text =
          'GPS position ${location.coordinatesLabel}. No street address was '
          'found here; type a name or address for it.';
    } else if (location.source == LocationSource.gps) {
      text =
          'From GPS (${location.coordinatesLabel}). The address is '
          'approximate; please check it.';
    } else {
      text = 'Selected location: ${location.coordinatesLabel}';
    }

    return Padding(
      padding: EdgeInsets.only(top: 6.h),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            location.source == LocationSource.gps
                ? Icons.my_location_rounded
                : Icons.place_outlined,
            size: 14.r,
            color: AppColors.textSecondary,
          ),
          SizedBox(width: 6.w),
          Expanded(
            child: Text(
              text,
              key: const ValueKey('selected-location-note'),
              style: AppTypography.body(
                color: AppColors.textSecondary,
                fontSize: 11.5.sp,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
