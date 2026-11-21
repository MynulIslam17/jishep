import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:gps_cielo/core/constants/app_colors.dart';
import 'package:gps_cielo/core/constants/app_typography.dart';
import 'package:gps_cielo/core/models/household_model.dart';
import 'package:gps_cielo/core/services/household_store.dart';
import 'package:gps_cielo/core/utils/search_range.dart';

/// Green used for "prayed" everywhere in the neighbors flow.
const Color prayedGreen = Color(0xFF16A34A);
const Color prayedGreenLight = Color(0xFFE8F8EE);

/// "18 m", "1.2 km" from [from] (default: the saved home), or null.
String? homeDistanceLabel(
  HouseholdModel household, {
  ({double latitude, double longitude})? from,
}) {
  final point =
      from ??
      (Get.isRegistered<HouseholdStore>()
          ? Get.find<HouseholdStore>().homePoint
          : null);
  if (point == null) return null;
  final meters = SearchRange.distanceMeters(
    point.latitude,
    point.longitude,
    household.latitude,
    household.longitude,
  );
  return meters == null ? null : SearchRange.formatHomeDistance(meters);
}

/// One home in a list (Figma "Household row"): number, house icon, name or
/// "Neighbor", street, "CITY, ST ZIP · 18 m", then a Pray / Prayed chip and a
/// chevron. Tapping the row opens the household; the chip prays.
class HouseholdRow extends StatelessWidget {
  const HouseholdRow({
    required this.household,
    this.onTap,
    this.onPrayToggle,
    this.number,
    this.from,
    this.showChevron = true,
    super.key,
  });

  final HouseholdModel household;
  final VoidCallback? onTap;

  /// Null hides the chip's action (e.g. a preview before setup is saved).
  final VoidCallback? onPrayToggle;

  /// Number in the badge (default: the household's distance rank).
  final int? number;

  /// Point distances are measured from (default: the saved home).
  final ({double latitude, double longitude})? from;
  final bool showChevron;

  @override
  Widget build(BuildContext context) {
    final distance = homeDistanceLabel(household, from: from);
    final city = household.cityStateZip;
    final detail = [if (city.isNotEmpty) city, ?distance].join(' · ');

    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(14.r),
      child: InkWell(
        key: ValueKey('household-row-${household.id}'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(14.r),
        child: Container(
          padding: EdgeInsets.fromLTRB(12.w, 11.h, 8.w, 11.h),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14.r),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              NumberBadge(number: number ?? household.number),
              SizedBox(width: 10.w),
              const HouseTile(),
              SizedBox(width: 10.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      household.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.heading(
                        color: AppColors.textPrimary,
                        fontSize: 14.sp,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 1.h),
                    Text(
                      household.address,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.body(
                        color: AppColors.textSecondary,
                        fontSize: 11.5.sp,
                      ),
                    ),
                    if (detail.isNotEmpty)
                      Text(
                        detail,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.body(
                          color: AppColors.textMuted,
                          fontSize: 10.5.sp,
                        ),
                      ),
                  ],
                ),
              ),
              SizedBox(width: 6.w),
              PrayChip(
                key: ValueKey('pray-chip-${household.id}'),
                prayed: household.isPrayed,
                onPressed: onPrayToggle,
              ),
              if (showChevron)
                Icon(
                  Icons.chevron_right_rounded,
                  size: 20.r,
                  color: AppColors.textMuted,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Small navy circle with a number.
class NumberBadge extends StatelessWidget {
  const NumberBadge({required this.number, super.key});

  final int number;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 24.r,
      height: 24.r,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: AppColors.primaryNavy,
        shape: BoxShape.circle,
      ),
      child: FittedBox(
        child: Padding(
          padding: EdgeInsets.all(3.r),
          child: Text(
            '$number',
            style: AppTypography.label(
              color: Colors.white,
              fontSize: 11.sp,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

/// Light rounded square with a house icon.
class HouseTile extends StatelessWidget {
  const HouseTile({this.size = 34, super.key});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size.r,
      height: size.r,
      decoration: BoxDecoration(
        color: const Color(0xFFE8EFF7),
        borderRadius: BorderRadius.circular(9.r),
      ),
      child: Icon(
        Icons.home_outlined,
        size: (size * 0.55).r,
        color: AppColors.primaryNavy,
      ),
    );
  }
}

/// "♡ Pray" (outlined) or "✓ Prayed" (green pill).
class PrayChip extends StatelessWidget {
  const PrayChip({required this.prayed, this.onPressed, super.key});

  final bool prayed;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final child = Container(
      height: 28.h,
      padding: EdgeInsets.symmetric(horizontal: 10.w),
      decoration: BoxDecoration(
        color: prayed ? prayedGreenLight : AppColors.surface,
        borderRadius: BorderRadius.circular(20.r),
        border: Border.all(
          color: prayed ? prayedGreenLight : AppColors.primaryNavy,
          width: 1.2,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            prayed ? Icons.check_rounded : Icons.favorite_border_rounded,
            size: 13.r,
            color: prayed ? prayedGreen : AppColors.primaryNavy,
          ),
          SizedBox(width: 4.w),
          Text(
            prayed ? 'Prayed' : 'Pray',
            style: AppTypography.label(
              color: prayed ? prayedGreen : AppColors.primaryNavy,
              fontSize: 11.5.sp,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
    if (onPressed == null) return child;
    return Semantics(
      button: true,
      label: prayed ? 'Prayed. Tap to undo' : 'Pray',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPressed,
        child: Padding(
          // A larger tap target than the pill itself.
          padding: EdgeInsets.symmetric(vertical: 6.h, horizontal: 2.w),
          child: child,
        ),
      ),
    );
  }
}
