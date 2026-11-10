import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:gps_cielo/core/constants/app_colors.dart';
import 'package:gps_cielo/core/constants/app_typography.dart';
import 'package:gps_cielo/core/services/location_service.dart';
import 'package:gps_cielo/core/utils/search_range.dart';
import 'package:gps_cielo/core/utils/system_ui_config.dart';
import 'package:gps_cielo/features/auth/presentation/controllers/location_setup_controller.dart';
import 'package:gps_cielo/shared/widgets/buttons/app_primary_button.dart';
import 'package:gps_cielo/shared/widgets/inputs/address_autocomplete.dart';
import 'package:gps_cielo/shared/widgets/inputs/selected_location_note.dart';
import 'package:gps_cielo/shared/widgets/layout/collapsing_header_scroll_view.dart';
import 'package:gps_cielo/shared/widgets/map/household_osm_map.dart';

/// First-run setup: home address, neighborhood range and daily prayer goal,
/// with a live map of the households the Prayer List will use.
class LocationSetupScreen extends GetView<LocationSetupController> {
  const LocationSetupScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      // Light status icons on the navy header; dark nav icons on the white
      // bottom bar.
      value: SystemUiConfig.darkOverlay.copyWith(
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: GestureDetector(
          // Tap outside the field closes the keyboard and suggestions.
          onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
          behavior: HitTestBehavior.translucent,
          child: CollapsingHeaderScrollView(
            title: 'Set up your home',
            subtitle: const Text(
              'Your neighbors are found around this address',
            ),
            pinnedHeight: 46.h,
            pinned: const _SummaryStrip(),
            slivers: [
              SliverPadding(
                padding: EdgeInsets.fromLTRB(16.w, 14.h, 16.w, 24.h),
                sliver: SliverList.list(
                  children: [
                    const _AddressSection(),
                    SizedBox(height: 14.h),
                    const _MapSection(),
                    SizedBox(height: 14.h),
                    const _RangeSection(),
                    SizedBox(height: 14.h),
                    const _GoalSection(),
                    SizedBox(height: 10.h),
                    _signOutLink(),
                  ],
                ),
              ),
            ],
          ),
        ),
        // Always reachable, out of the way while typing.
        bottomNavigationBar: keyboardOpen ? null : const _ConfirmBar(),
      ),
    );
  }

  Widget _signOutLink() {
    return Center(
      child: TextButton(
        key: const ValueKey('setup-sign-out'),
        onPressed: controller.signOut,
        child: Obx(() {
          final email = controller.accountLabel.value;
          return Text(
            email.isEmpty
                ? 'Not you? Sign out'
                : 'Signed in as $email · Sign out',
            textAlign: TextAlign.center,
            style: AppTypography.label(
              color: AppColors.textSecondary,
              fontSize: 12.5.sp,
              fontWeight: FontWeight.w600,
            ),
          );
        }),
      ),
    );
  }
}

/// Sticky line under the header: where home is and how many neighbors.
class _SummaryStrip extends GetView<LocationSetupController> {
  const _SummaryStrip();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16.w),
      child: Obx(() {
        final has = controller.hasLocation;
        return Row(
          children: [
            Icon(
              has ? Icons.home_rounded : Icons.home_outlined,
              size: 18.r,
              color: has ? AppColors.primaryNavy : AppColors.textSecondary,
            ),
            SizedBox(width: 8.w),
            Expanded(
              child: Text(
                has
                    ? controller.previewSummary
                    : 'Choose your home to see your neighbors',
                key: const ValueKey('setup-summary'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.label(
                  color: has ? AppColors.textPrimary : AppColors.textSecondary,
                  fontSize: 13.sp,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (has && controller.isLoadingPreview.value)
              SizedBox(
                width: 14.r,
                height: 14.r,
                child: const CircularProgressIndicator(strokeWidth: 2),
              ),
          ],
        );
      }),
    );
  }
}

/// A white card with a numbered title.
class _Section extends StatelessWidget {
  const _Section({
    required this.step,
    required this.title,
    required this.child,
    this.subtitle,
  });

  final int step;
  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(16.r),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 11.r,
                backgroundColor: AppColors.primaryNavy,
                child: Text(
                  '$step',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 11.sp,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              SizedBox(width: 10.w),
              Expanded(
                child: Text(
                  title,
                  style: AppTypography.heading(
                    color: AppColors.primaryNavy,
                    fontSize: 15.sp,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          if (subtitle != null) ...[
            SizedBox(height: 6.h),
            Text(
              subtitle!,
              style: AppTypography.body(
                color: AppColors.textSecondary,
                fontSize: 12.5.sp,
                height: 1.35,
              ),
            ),
          ],
          SizedBox(height: 12.h),
          child,
        ],
      ),
    );
  }
}

class _AddressSection extends GetView<LocationSetupController> {
  const _AddressSection();

  @override
  Widget build(BuildContext context) {
    return _Section(
      step: 1,
      title: 'Your home address',
      subtitle: 'Start typing and pick your address from the list.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Obx(() {
            final near = controller.selectedLocation.value;
            return AddressAutocomplete(
              key: const ValueKey('setup-address'),
              controller: controller.addressController,
              onSelected: controller.selectSuggestion,
              nearLatitude: near?.latitude,
              nearLongitude: near?.longitude,
              fieldBuilder: (context, fieldController, focusNode) =>
                  _AddressField(
                    controller: fieldController,
                    focusNode: focusNode,
                  ),
            );
          }),
          Obx(
            () => SelectedLocationNote(
              location: controller.selectedLocation.value,
            ),
          ),
          SizedBox(height: 12.h),
          Obx(
            () => OutlinedButton.icon(
              key: const ValueKey('use-current-location'),
              onPressed: controller.isLocating.value
                  ? null
                  : controller.useCurrentLocation,
              icon: controller.isLocating.value
                  ? SizedBox(
                      width: 16.r,
                      height: 16.r,
                      child: const CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(Icons.my_location_rounded, size: 18.r),
              label: Text(
                controller.isLocating.value
                    ? 'Finding your location…'
                    : 'Use my current location',
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primaryNavy,
                minimumSize: Size.fromHeight(44.h),
                side: const BorderSide(color: AppColors.border),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12.r),
                ),
                textStyle: AppTypography.label(
                  fontSize: 13.5.sp,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          Obx(() {
            final error = controller.locationError.value;
            if (error == null) return const SizedBox.shrink();
            return _LocationErrorNote(
              error: error,
              onFix: controller.openLocationSettings,
              onRetry: controller.useCurrentLocation,
            );
          }),
        ],
      ),
    );
  }
}

class _AddressField extends StatelessWidget {
  const _AddressField({required this.controller, required this.focusNode});

  final TextEditingController controller;
  final FocusNode focusNode;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([controller, focusNode]),
      builder: (context, _) {
        final focused = focusNode.hasFocus;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            color: AppColors.inputSurface,
            borderRadius: BorderRadius.circular(12.r),
            border: Border.all(
              color: focused ? AppColors.primaryNavy : AppColors.border,
              width: focused ? 1.4 : 1,
            ),
          ),
          padding: EdgeInsets.only(left: 12.w),
          child: Row(
            children: [
              Icon(
                Icons.search_rounded,
                color: AppColors.textSecondary,
                size: 20.r,
              ),
              SizedBox(width: 8.w),
              Expanded(
                child: TextField(
                  controller: controller,
                  focusNode: focusNode,
                  textInputAction: TextInputAction.search,
                  textCapitalization: TextCapitalization.words,
                  style: AppTypography.label(
                    color: AppColors.textPrimary,
                    fontSize: 14.sp,
                    fontWeight: FontWeight.w600,
                  ),
                  decoration: InputDecoration(
                    hintText: 'e.g. House 12, Road 5, Demra, Dhaka',
                    hintStyle: AppTypography.body(
                      color: AppColors.textSecondary,
                      fontSize: 13.5.sp,
                    ),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(vertical: 14.h),
                  ),
                ),
              ),
              if (controller.text.isNotEmpty)
                IconButton(
                  key: const ValueKey('clear-address'),
                  tooltip: 'Clear',
                  onPressed: () {
                    controller.clear();
                    focusNode.requestFocus();
                  },
                  icon: Icon(
                    Icons.close_rounded,
                    size: 18.r,
                    color: AppColors.textSecondary,
                  ),
                )
              else
                SizedBox(width: 12.w),
            ],
          ),
        );
      },
    );
  }
}

class _LocationErrorNote extends StatelessWidget {
  const _LocationErrorNote({
    required this.error,
    required this.onFix,
    required this.onRetry,
  });

  final LocationException error;
  final VoidCallback onFix;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final needsSettings =
        error.reason == LocationFailure.servicesDisabled ||
        error.reason == LocationFailure.permissionDeniedForever;
    return Container(
      key: const ValueKey('location-error'),
      margin: EdgeInsets.only(top: 10.h),
      padding: EdgeInsets.all(12.r),
      decoration: BoxDecoration(
        color: AppColors.danger.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(color: AppColors.danger.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.location_off_outlined,
            size: 18.r,
            color: AppColors.danger,
          ),
          SizedBox(width: 8.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  error.message,
                  style: AppTypography.body(
                    color: AppColors.textPrimary,
                    fontSize: 12.5.sp,
                    height: 1.35,
                  ),
                ),
                SizedBox(height: 4.h),
                Text(
                  'You can also type your address above.',
                  style: AppTypography.body(
                    color: AppColors.textSecondary,
                    fontSize: 12.sp,
                  ),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: needsSettings ? onFix : onRetry,
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      foregroundColor: AppColors.primaryNavy,
                    ),
                    child: Text(needsSettings ? 'Open settings' : 'Try again'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MapSection extends StatefulWidget {
  const _MapSection();

  @override
  State<_MapSection> createState() => _MapSectionState();
}

class _MapSectionState extends State<_MapSection> {
  final _handle = HouseholdMapHandle();

  LocationSetupController get controller => Get.find();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 230.h,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: const Color(0xFFE8EDF5),
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(color: AppColors.border),
      ),
      child: Obx(() {
        final location = controller.selectedLocation.value;
        if (location == null) return const _MapPlaceholder();
        final households = controller.previewHouseholds.toList();
        return Stack(
          children: [
            Positioned.fill(
              child: HouseholdOsmMap(
                key: const ValueKey('setup-map'),
                centerLatitude: location.latitude,
                centerLongitude: location.longitude,
                households: households,
                areaMeters: controller.rangeKm.value * 1000,
                handle: _handle,
                // The page scrolls; use the buttons to zoom.
                interactive: false,
                markerSize: 30,
              ),
            ),
            Positioned(
              left: 10.w,
              top: 10.h,
              child: _MapBadge(text: controller.previewSummary),
            ),
            Positioned(
              right: 10.w,
              bottom: 10.h,
              child: Column(
                children: [
                  _MapButton(icon: Icons.add_rounded, onTap: _handle.zoomIn),
                  SizedBox(height: 6.h),
                  _MapButton(
                    icon: Icons.remove_rounded,
                    onTap: _handle.zoomOut,
                  ),
                  SizedBox(height: 6.h),
                  _MapButton(
                    icon: Icons.center_focus_strong_rounded,
                    onTap: _handle.recenter,
                  ),
                ],
              ),
            ),
            if (controller.previewError.value)
              Positioned(
                left: 10.w,
                bottom: 10.h,
                child: ActionChip(
                  avatar: Icon(Icons.refresh_rounded, size: 16.r),
                  label: const Text('Retry'),
                  onPressed: controller.retryPreview,
                ),
              ),
          ],
        );
      }),
    );
  }
}

class _MapPlaceholder extends StatelessWidget {
  const _MapPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Center(
      key: const ValueKey('map-placeholder'),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 24.w),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.map_outlined,
              size: 38.r,
              color: AppColors.primaryNavy.withValues(alpha: 0.5),
            ),
            SizedBox(height: 10.h),
            Text(
              'Your neighborhood map appears here',
              textAlign: TextAlign.center,
              style: AppTypography.label(
                color: AppColors.primaryNavy,
                fontSize: 14.sp,
                fontWeight: FontWeight.w700,
              ),
            ),
            SizedBox(height: 4.h),
            Text(
              'Pick your address or use your current location.',
              textAlign: TextAlign.center,
              style: AppTypography.body(
                color: AppColors.textSecondary,
                fontSize: 12.5.sp,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MapBadge extends StatelessWidget {
  const _MapBadge({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(maxWidth: 240.w),
      padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 6.h),
      decoration: BoxDecoration(
        color: AppColors.primaryNavy,
        borderRadius: BorderRadius.circular(20.r),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Text(
        text,
        key: const ValueKey('map-badge'),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppTypography.label(
          color: Colors.white,
          fontSize: 11.5.sp,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _MapButton extends StatelessWidget {
  const _MapButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: const CircleBorder(),
      elevation: 2,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 34.r,
          height: 34.r,
          child: Icon(icon, size: 18.r, color: AppColors.primaryNavy),
        ),
      ),
    );
  }
}

class _RangeSection extends GetView<LocationSetupController> {
  const _RangeSection();

  @override
  Widget build(BuildContext context) {
    return _Section(
      step: 2,
      title: 'Neighborhood range',
      subtitle:
          'Households within this distance of your home make up your '
          'Prayer List.',
      child: Obx(() {
        final selected = controller.rangeKm.value;
        return Wrap(
          spacing: 8.w,
          runSpacing: 8.h,
          children: [
            for (final km in SearchRange.distanceOptionsKm)
              _Pill(
                key: ValueKey('range-$km'),
                label: SearchRange.formatKm(km),
                selected: km == selected,
                onTap: () => controller.setRange(km),
              ),
          ],
        );
      }),
    );
  }
}

class _GoalSection extends GetView<LocationSetupController> {
  const _GoalSection();

  @override
  Widget build(BuildContext context) {
    return _Section(
      step: 3,
      title: 'Daily prayer goal',
      subtitle: 'How many neighbors to pray for each day.',
      child: Obx(() {
        final goal = controller.dailyGoal.value;
        final days = controller.cycleDays;
        final total = controller.previewHouseholds.length;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8.w,
              runSpacing: 8.h,
              children: [
                for (final g in LocationSetupController.dailyGoals)
                  _Pill(
                    key: ValueKey('goal-$g'),
                    label: '$g a day',
                    selected: g == goal,
                    onTap: () => controller.setDailyGoal(g),
                  ),
              ],
            ),
            if (days != null) ...[
              SizedBox(height: 12.h),
              Row(
                children: [
                  Icon(
                    Icons.event_repeat_rounded,
                    size: 16.r,
                    color: AppColors.primaryGold,
                  ),
                  SizedBox(width: 6.w),
                  Expanded(
                    child: Text(
                      'You’ll pray for all $total neighbors in about '
                      '$days ${days == 1 ? 'day' : 'days'}.',
                      key: const ValueKey('cycle-days'),
                      style: AppTypography.body(
                        color: AppColors.textSecondary,
                        fontSize: 12.5.sp,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            SizedBox(height: 8.h),
            Text(
              'You can change the range and goal later in Profile.',
              style: AppTypography.body(
                color: AppColors.textSecondary,
                fontSize: 11.5.sp,
              ),
            ),
          ],
        );
      }),
    );
  }
}

/// Selectable option pill (no ripple; the selection animates).
class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 9.h),
          decoration: BoxDecoration(
            color: selected ? AppColors.primaryNavy : AppColors.inputSurface,
            borderRadius: BorderRadius.circular(20.r),
            border: Border.all(
              color: selected ? AppColors.primaryNavy : AppColors.border,
            ),
          ),
          child: Text(
            label,
            style: AppTypography.label(
              color: selected ? Colors.white : AppColors.textPrimary,
              fontSize: 13.sp,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

class _ConfirmBar extends GetView<LocationSetupController> {
  const _ConfirmBar();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: const Border(top: BorderSide(color: AppColors.border)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(16.w, 10.h, 16.w, 10.h),
          child: Obx(
            () => AppPrimaryButton(
              key: const ValueKey('confirm-home'),
              label: controller.hasLocation
                  ? 'Save my home and continue'
                  : 'Continue',
              isLoading: controller.isSubmitting.value,
              onPressed: controller.confirmLocation,
            ),
          ),
        ),
      ),
    );
  }
}
