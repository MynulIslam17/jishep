import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:gps_cielo/core/constants/app_colors.dart';
import 'package:gps_cielo/core/constants/app_strings.dart';
import 'package:gps_cielo/core/constants/app_typography.dart';
import 'package:gps_cielo/core/models/household_model.dart';
import 'package:gps_cielo/features/neighborhood/presentation/controllers/neighborhood_controller.dart';
import 'package:gps_cielo/features/profile/presentation/widgets/change_home_address.dart';
import 'package:gps_cielo/shared/widgets/bottom_sheets/household_detail_bottom_sheet.dart';
import 'package:gps_cielo/shared/widgets/dialogs/app_confirmation_dialog.dart';
import 'package:gps_cielo/shared/widgets/household/household_row.dart';
import 'package:gps_cielo/shared/widgets/inputs/app_search_field.dart';
import 'package:gps_cielo/shared/widgets/inputs/app_segmented_switch.dart';
import 'package:gps_cielo/shared/widgets/layout/collapsing_header_scroll_view.dart';
import 'package:gps_cielo/shared/widgets/map/household_osm_map.dart';

/// Figma "My Neighborhood": navy header with search, a Map | List switch,
/// the nearest N homes (navy = to pray, green = prayed this round).
class NeighborhoodScreen extends GetView<NeighborhoodController> {
  const NeighborhoodScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: CollapsingHeaderScrollView(
        title: 'My Neighborhood',
        subtitle: Obx(() {
          final n = controller.households.length;
          final where = controller.centerLabel.value;
          final lead = controller.isTemporary.value
              ? 'Viewing'
              : 'Nearest $n ${n == 1 ? 'home' : 'homes'}';
          return Text(
            where.isEmpty ? lead : '$lead · $where',
            key: const ValueKey('neighborhood-subtitle'),
          );
        }),
        actions: [
          HeaderIconButton(
            key: const ValueKey('neighborhood-search'),
            icon: Icons.search_rounded,
            tooltip: 'Look around another place',
            onPressed: () => _openSearch(context),
          ),
        ],
        onRefresh: controller.loadHouseholds,
        pinnedHeight: 60.h,
        pinned: _buildPinnedStrip(),
        slivers: [Obx(() => _buildBody(context))],
      ),
    );
  }

  /// "50 households · 12 prayed" and the Map / List switch.
  Widget _buildPinnedStrip() {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16.w),
      child: Row(
        children: [
          Expanded(
            child: Obx(() {
              final n = controller.households.length;
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$n ${n == 1 ? 'household' : 'households'} · '
                    '${controller.prayedCount} prayed',
                    key: const ValueKey('area-count'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.heading(
                      color: AppColors.textPrimary,
                      fontSize: 14.sp,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    controller.areaSourceNote.value ?? 'Nearest first',
                    key: const ValueKey('area-source-note'),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.body(
                      color: AppColors.textSecondary,
                      fontSize: 12.sp,
                    ),
                  ),
                ],
              );
            }),
          ),
          SizedBox(width: 12.w),
          SizedBox(
            width: 150.w,
            child: Obx(
              () => AppSegmentedSwitch(
                key: const ValueKey('view-mode'),
                labels: const ['Map', 'List'],
                icons: const [Icons.map_outlined, Icons.view_list_rounded],
                selectedIndex:
                    controller.viewMode.value == NeighborhoodViewMode.map
                    ? 0
                    : 1,
                onChanged: (i) => controller.switchViewMode(
                  i == 0 ? NeighborhoodViewMode.map : NeighborhoodViewMode.list,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Padding around the list, loading and empty states (the map is full
  /// width, edge to edge).
  static EdgeInsets get _pad => EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 24.h);

  Widget _buildBody(BuildContext context) {
    final homes = controller.households.toList();
    final banner = controller.isTemporary.value ? _buildViewingBanner() : null;

    if (!(controller.isLoading.value && homes.isEmpty) &&
        homes.isNotEmpty &&
        controller.viewMode.value == NeighborhoodViewMode.map) {
      // Map view: the map fills everything from below the Map | List strip
      // down to the bottom navigation bar.
      return SliverLayoutBuilder(
        builder: (context, constraints) {
          final height = math.max(constraints.remainingPaintExtent, 320.h);
          return SliverToBoxAdapter(
            child: SizedBox(
              height: height,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (banner != null)
                    Padding(
                      padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 8.h),
                      child: banner,
                    ),
                  Expanded(child: _buildMap(context, homes)),
                ],
              ),
            ),
          );
        },
      );
    }

    final Widget content;
    if (controller.isLoading.value && homes.isEmpty) {
      content = SizedBox(
        height: 160.h,
        child: const Center(child: CircularProgressIndicator()),
      );
    } else if (homes.isEmpty) {
      content = _buildEmpty();
    } else {
      return SliverPadding(
        padding: _pad,
        sliver: SliverMainAxisGroup(
          slivers: [
            if (banner != null)
              SliverPadding(
                padding: EdgeInsets.only(bottom: 12.h),
                sliver: SliverToBoxAdapter(child: banner),
              ),
            SliverList.separated(
              key: const ValueKey('neighborhood-list'),
              itemCount: homes.length,
              separatorBuilder: (context, _) => SizedBox(height: 10.h),
              itemBuilder: (context, i) => _row(context, homes[i], i + 1),
            ),
          ],
        ),
      );
    }
    return SliverPadding(
      padding: _pad,
      sliver: SliverToBoxAdapter(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (banner != null) ...[banner, SizedBox(height: 12.h)],
            content,
          ],
        ),
      ),
    );
  }

  Widget _row(BuildContext context, HouseholdModel household, int number) {
    void pray() => controller.togglePray(household);
    return HouseholdRow(
      key: ValueKey('area-${household.id}'),
      household: household,
      number: number,
      // Distances from the place on screen (home or the searched place).
      from: _center,
      onPrayToggle: pray,
      onTap: () => _openHousehold(context, household),
    );
  }

  ({double latitude, double longitude})? get _center {
    final lat = controller.centerLatitude.value;
    final lng = controller.centerLongitude.value;
    if (lat == null || lng == null) return null;
    return (latitude: lat, longitude: lng);
  }

  void _openHousehold(BuildContext context, HouseholdModel household) {
    HouseholdDetailBottomSheet.show(
      context,
      household: household,
      onPrayToggle: () => controller.togglePray(household),
      onUpdated: controller.updateHousehold,
    );
  }

  Widget _buildEmpty() {
    final unavailable = controller.areaUnavailable.value;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 24.h),
      child: Column(
        children: [
          Icon(
            Icons.travel_explore_rounded,
            size: 40.r,
            color: AppColors.textMuted,
          ),
          SizedBox(height: 10.h),
          Text(
            unavailable
                ? AppStrings.areaUnavailable
                : 'No households near this place yet',
            key: const ValueKey('neighborhood-empty'),
            textAlign: TextAlign.center,
            style: AppTypography.heading(
              color: AppColors.textPrimary,
              fontSize: 15.sp,
              fontWeight: FontWeight.w700,
            ),
          ),
          SizedBox(height: 4.h),
          Text(
            unavailable
                ? '${AppStrings.areasAvailable}. ${AppStrings.areaComingSoon}'
                : 'Search another place, or change your home address.',
            textAlign: TextAlign.center,
            style: AppTypography.body(
              color: AppColors.textSecondary,
              fontSize: 13.sp,
            ),
          ),
          if (!controller.isTemporary.value) ...[
            SizedBox(height: 12.h),
            ChangeHomeAddress.button(),
          ],
        ],
      ),
    );
  }

  /// "● 38 to pray  ● 12 prayed this round".
  Widget _buildLegend() {
    Widget item(Color color, String text) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        HouseMarker(size: 15.r, color: color),
        SizedBox(width: 3.w),
        Text(
          text,
          style: AppTypography.body(
            color: AppColors.textSecondary,
            fontSize: 12.sp,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
    return Container(
      key: const ValueKey('map-legend'),
      padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 8.h),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20.r),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 8),
        ],
      ),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 16.w,
        runSpacing: 4.h,
        children: [
          item(AppColors.primaryNavy, '${controller.toPrayCount} to pray'),
          item(prayedGreen, '${controller.prayedCount} prayed this round'),
        ],
      ),
    );
  }

  /// Full-width map (no card), with the chip, zoom buttons and legend on top.
  Widget _buildMap(BuildContext context, List<HouseholdModel> homes) {
    final center = _center;
    return Container(
      key: const ValueKey('neighborhood-map'),
      color: const Color(0xFFF1F5F9),
      child: Stack(
        children: [
          if (center != null)
            Positioned.fill(
              child: HouseholdOsmMap(
                centerLatitude: center.latitude,
                centerLongitude: center.longitude,
                households: homes,
                handle: controller.mapHandle,
                markerSize: 30,
                onHouseholdTap: (h) => _openHousehold(context, h),
              ),
            )
          else
            Center(
              child: Text(
                'Set your address to see your neighborhood map',
                style: AppTypography.label(
                  color: AppColors.textSecondary,
                  fontSize: 12.sp,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          Positioned(
            top: 12.h,
            left: 12.w,
            child: Container(
              key: const ValueKey('map-chip'),
              padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 6.h),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20.r),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 6,
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.home_rounded,
                    size: 14.r,
                    color: AppColors.primaryNavy,
                  ),
                  SizedBox(width: 4.w),
                  Text(
                    'Nearest ${homes.length} homes',
                    style: AppTypography.label(
                      color: AppColors.primaryNavy,
                      fontSize: 11.5.sp,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (center != null)
            Positioned(
              top: 12.h,
              right: 12.w,
              child: Column(
                children: [
                  _zoomButton(Icons.add_rounded, controller.zoomIn),
                  SizedBox(height: 6.h),
                  _zoomButton(Icons.remove_rounded, controller.zoomOut),
                ],
              ),
            ),
          Positioned(
            left: 12.w,
            right: 12.w,
            bottom: 36.h,
            child: Center(child: _buildLegend()),
          ),
        ],
      ),
    );
  }

  Widget _zoomButton(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32.r,
        height: 32.r,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8.r),
          border: Border.all(color: AppColors.border),
        ),
        child: Icon(icon, size: 18.r, color: AppColors.primaryNavy),
      ),
    );
  }

  /// While looking at another place: say so, go back, or make it home.
  Widget _buildViewingBanner() {
    final place = controller.centerLabel.value;
    return Container(
      key: const ValueKey('viewing-banner'),
      padding: EdgeInsets.fromLTRB(12.w, 10.h, 12.w, 4.h),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F3FF),
        borderRadius: BorderRadius.circular(14.r),
        border: Border.all(color: const Color(0xFFDDD6FE)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.travel_explore_rounded,
                size: 18.r,
                color: const Color(0xFF7C3AED),
              ),
              SizedBox(width: 8.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Viewing near $place',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.label(
                        color: AppColors.textPrimary,
                        fontSize: 13.sp,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 2.h),
                    Text(
                      'Just looking around: your home and Prayer List are '
                      'unchanged.',
                      style: AppTypography.body(
                        color: AppColors.textSecondary,
                        fontSize: 11.5.sp,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          Wrap(
            spacing: 4.w,
            children: [
              TextButton.icon(
                key: const ValueKey('back-to-home'),
                onPressed: controller.useHomeAddress,
                icon: Icon(Icons.home_outlined, size: 16.r),
                label: const Text('Back to my home'),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.primaryNavy,
                ),
              ),
              TextButton.icon(
                key: const ValueKey('set-as-home'),
                onPressed: controller.isSavingHome.value
                    ? null
                    : () => AppConfirmationDialog.show(
                        title: 'Set as your home?',
                        message:
                            'Your home address will change to "$place". Your '
                            'Prayer List, Neighborhood and Home will use the '
                            'homes nearest it.',
                        confirmLabel: 'Set as home',
                        onConfirm: controller.setSearchedPlaceAsHome,
                      ),
                icon: Icon(Icons.push_pin_outlined, size: 16.r),
                label: const Text('Set as my home'),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF7C3AED),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Bottom sheet: search an address or use GPS to look around there.
  void _openSearch(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheet) {
        void done() => Navigator.of(sheet).maybePop();
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(sheet).viewInsets.bottom,
          ),
          child: Container(
            key: const ValueKey('neighborhood-search-sheet'),
            padding: EdgeInsets.fromLTRB(
              20.w,
              16.h,
              20.w,
              20.h + MediaQuery.of(sheet).padding.bottom,
            ),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24.r)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Look around another place',
                  style: AppTypography.heading(
                    color: AppColors.textPrimary,
                    fontSize: 17.sp,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: 4.h),
                Text(
                  'See the nearest homes there. Your home and Prayer List '
                  "don't change.",
                  style: AppTypography.body(
                    color: AppColors.textSecondary,
                    fontSize: 12.5.sp,
                  ),
                ),
                SizedBox(height: 14.h),
                Obx(
                  () => AppSearchField(
                    controller: controller.searchController,
                    nearLatitude: controller.homeLatitude,
                    nearLongitude: controller.homeLongitude,
                    isLocating: controller.isLocating.value,
                    onAddressSelected: (suggestion) {
                      done();
                      controller.selectSuggestion(suggestion);
                    },
                    onSubmitted: (_) {
                      done();
                      controller.searchNeighborhood();
                    },
                    onGpsPressed: () {
                      done();
                      controller.useCurrentLocation();
                    },
                  ),
                ),
                if (controller.isTemporary.value) ...[
                  SizedBox(height: 8.h),
                  TextButton.icon(
                    key: const ValueKey('search-back-to-home'),
                    onPressed: () {
                      done();
                      controller.useHomeAddress();
                    },
                    icon: Icon(Icons.home_outlined, size: 16.r),
                    label: const Text('Back to my home'),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
