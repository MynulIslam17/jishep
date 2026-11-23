import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:gps_cielo/core/constants/app_colors.dart';
import 'package:gps_cielo/core/constants/app_typography.dart';
import 'package:gps_cielo/core/models/household_model.dart';
import 'package:gps_cielo/core/services/address_check_service.dart';
import 'package:gps_cielo/core/services/household_store.dart';

/// "Check address" in the household sheet: asks the backend (Melissa) to
/// verify the address and say whether it is a home or a business. Shown
/// only with `FeatureFlags.addressChecks` and only when the household has a
/// full street address. Each check may cost Melissa credits, so it runs
/// only when the user taps.
class AddressCheckTile extends StatefulWidget {
  const AddressCheckTile({
    required this.household,
    this.service,
    this.onOwner,
    super.key,
  });

  final HouseholdModel household;
  final AddressCheckService? service;

  /// Called with the recorded owner's name (or null) after a check.
  final ValueChanged<String?>? onOwner;

  @override
  State<AddressCheckTile> createState() => _AddressCheckTileState();
}

class _AddressCheckTileState extends State<AddressCheckTile> {
  AddressCheck? _result;
  String? _error;
  bool _loading = false;

  Future<void> _check() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final service = widget.service ?? AddressCheckService();
      final result = await service.check(widget.household);
      // Every list showing this home uses the owner name from now on.
      if (Get.isRegistered<HouseholdStore>()) {
        Get.find<HouseholdStore>().setOwnerName(
          widget.household.id,
          result.ownerName,
        );
      }
      widget.onOwner?.call(result.ownerName);
      if (mounted) setState(() => _result = result);
    } on AddressCheckException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Address check is unavailable right now.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (AddressCheckService.partsOf(widget.household) == null) {
      return const SizedBox.shrink();
    }
    final result = _result;
    final style = AppTypography.body(
      color: AppColors.textSecondary,
      fontSize: 12.sp,
    );
    return Container(
      key: const ValueKey('address-check'),
      width: double.infinity,
      padding: EdgeInsets.all(12.w),
      decoration: BoxDecoration(
        color: AppColors.inputSurface,
        borderRadius: BorderRadius.circular(12.r),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (result == null) ...[
            Text(
              'Look up this home with Melissa: whether it is a home or a '
              'business, what kind of building it is and, when enabled, '
              'the recorded owner (public property record).',
              style: style,
            ),
            SizedBox(height: 8.h),
            OutlinedButton.icon(
              key: const ValueKey('address-check-button'),
              onPressed: _loading ? null : _check,
              icon: _loading
                  ? SizedBox(
                      width: 14.w,
                      height: 14.w,
                      child: const CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.verified_outlined, size: 18),
              label: Text(_loading ? 'Checking…' : 'Check address'),
            ),
          ] else ...[
            Row(
              children: [
                Icon(
                  result.isVerified
                      ? Icons.verified
                      : Icons.help_outline_rounded,
                  size: 18,
                  color: result.isVerified
                      ? AppColors.success
                      : AppColors.textMuted,
                ),
                SizedBox(width: 6.w),
                Expanded(
                  child: Text(
                    result.summary,
                    key: const ValueKey('address-check-summary'),
                    style: AppTypography.body(
                      color: AppColors.textPrimary,
                      fontSize: 13.sp,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            if (result.verifiedLine != null) ...[
              SizedBox(height: 4.h),
              Text(
                [
                  result.verifiedLine,
                  result.verifiedCityStateZip,
                ].whereType<String>().join(', '),
                style: style,
              ),
            ],
            if (result.ownerName != null) ...[
              SizedBox(height: 6.h),
              Text(
                result.ownerIsCompany
                    ? '${HouseholdModel.ownerLabel} · company or trust'
                    : HouseholdModel.ownerLabel,
                style: AppTypography.body(
                  color: AppColors.textMuted,
                  fontSize: 11.sp,
                ),
              ),
              Text(
                result.ownerName!,
                key: const ValueKey('address-check-owner'),
                style: AppTypography.body(
                  color: AppColors.textPrimary,
                  fontSize: 14.sp,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                'Public property record. The owner may not live here.',
                style: AppTypography.body(
                  color: AppColors.textMuted,
                  fontSize: 11.sp,
                ),
              ),
            ] else if (result.propertyFound == true &&
                result.ownerRequested) ...[
              SizedBox(height: 4.h),
              Text(
                'No owner name on record.',
                key: const ValueKey('address-check-no-owner'),
                style: style,
              ),
            ],
            if (result.propertyLine != null) ...[
              SizedBox(height: 4.h),
              Text(
                result.propertyLine!,
                key: const ValueKey('address-check-property'),
                style: style,
              ),
            ],
            SizedBox(height: 4.h),
            Text(
              _sourceLine(result),
              style: AppTypography.body(
                color: AppColors.textMuted,
                fontSize: 11.sp,
              ),
            ),
          ],
          if (_error != null) ...[
            SizedBox(height: 6.h),
            Text(
              _error!,
              key: const ValueKey('address-check-error'),
              style: AppTypography.body(
                color: AppColors.danger,
                fontSize: 12.sp,
              ),
            ),
          ],
        ],
      ),
    );
  }

  static String _sourceLine(AddressCheck r) {
    if (r.isTestFixture) {
      return 'TEST FIXTURE: fictional data, not from Melissa';
    }
    final at = r.checkedAt?.toLocal();
    final date = at == null
        ? ''
        : ' · ${at.year}-${at.month.toString().padLeft(2, '0')}-'
              '${at.day.toString().padLeft(2, '0')}';
    return 'Address and property data by Melissa$date';
  }
}
