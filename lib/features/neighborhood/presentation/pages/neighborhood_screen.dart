import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:gps_cielo/core/constants/app_colors.dart';
import 'package:gps_cielo/core/constants/app_typography.dart';
import 'package:gps_cielo/features/neighborhood/presentation/controllers/neighborhood_controller.dart';
import 'package:gps_cielo/features/neighborhood/presentation/widgets/neighborhood_household_card.dart';
import 'package:gps_cielo/shared/widgets/map/household_osm_map.dart';
import 'package:gps_cielo/shared/widgets/bottom_sheets/household_detail_bottom_sheet.dart';
import 'package:gps_cielo/shared/widgets/inputs/app_segmented_switch.dart';
import 'package:gps_cielo/shared/widgets/layout/collapsing_header_scroll_view.dart';

class NeighborhoodScreen extends GetView<NeighborhoodController> {
  const NeighborhoodScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      // One scrolling page, like the Prayer list: the large title collapses,
      // the count and Map/List switch stay pinned, and the map scrolls away
      // so the list gets the whole screen. Drags that start on the map still
      // pan and zoom it (flutter_map claims them).
      body: NotificationListener<ScrollUpdateNotification>(
        // Load the next page shortly before the end is reached.
        onNotification: (notification) {
          if (notification.depth == 0 &&
              notification.metrics.extentAfter < 400) {
            controller.loadMore();
          }
          return false;
        },
        child: CollapsingHeaderScrollView(
          title: 'My Neighborhood',
          subtitle: Obx(() => Text(controller.rangeLabel)),
          onRefresh: controller.loadHouseholds,
          pinnedHeight: 64.h,
          pinned: _buildPinnedStrip(),
          slivers: [
            Obx(() {
              if (controller.viewMode.value != NeighborhoodViewMode.map) {
                return const SliverToBoxAdapter(child: SizedBox.shrink());
              }
              return SliverPadding(
                padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 0),
                sliver: SliverToBoxAdapter(child: _buildMapCard(context)),
              );
            }),
            SliverPadding(
              padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 0),
              sliver: Obx(_buildList),
            ),
          ],
        ),
      ),
    );
  }

  /// Count of households in range and the Map / List switch.
  Widget _buildPinnedStrip() {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16.w),
      child: Row(
        children: [
          Expanded(
            child: Obx(() {
              final total = controller.areaHouseholds.length;
              final shown = controller.pagedHouseholds.length;
              // Until the whole range is read, the count is a lower bound.
              final inRange = controller.areaComplete.value
                  ? '$total'
                  : '$total+';
              final String title;
              final String detail;
              if (controller.showAllInRange.value) {
                title =
                    '$inRange ${total == 1 ? 'household' : 'households'} '
                    'in range';
                detail = 'Nearest first \u2022 showing $shown';
              } else {
                final n = controller.households.length;
                title = controller.isTemporary.value
                    ? 'Nearest $n ${n == 1 ? 'home' : 'homes'} here'
                    : '$n ${n == 1 ? 'home' : 'homes'} in your neighborhood';
                detail = total == 0
                    ? 'Nearest first'
                    : 'Nearest first \u2022 $inRange in range';
              }
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    key: const ValueKey('area-count'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.heading(
                      color: AppColors.textPrimary,
                      fontSize: 14.sp,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SizedBox(height: 2.h),
                  Text(
                    detail,
                    key: const ValueKey('paging-status'),
                    maxLines: 1,
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

  /// Every household in range, nearest first, a page at a time.
  Widget _buildList() {
    if (controller.isLoading.value && controller.areaHouseholds.isEmpty) {
      return SliverToBoxAdapter(
        child: SizedBox(
          height: 160.h,
          child: const Center(child: CircularProgressIndicator()),
        ),
      );
    }
    final items = controller.pagedHouseholds;
    if (items.isEmpty) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 24.h),
          child: Text(
            'No households in range yet. Search another place on Home, or '
            'choose a larger search range in Profile \u203a Prayer '
            'preferences.',
            textAlign: TextAlign.center,
            style: AppTypography.body(
              color: AppColors.textSecondary,
              fontSize: 13.sp,
            ),
          ),
        ),
      );
    }
    final hasMore = controller.hasMore;
    final loadingMore = controller.isLoadingMore.value;
    final showAll = controller.showAllInRange.value;
    final neighborhoodSize = controller.households.length;
    // In "all in range", say first that only the neighborhood counts.
    final lead = showAll ? 1 : 0;
    return SliverList.separated(
      key: const ValueKey('neighborhood-list'),
      itemCount: lead + items.length + 1,
      separatorBuilder: (context, _) => SizedBox(height: 10.h),
      itemBuilder: (context, i) {
        if (showAll && i == 0) return _buildAllInRangeNote(neighborhoodSize);
        final index = i - lead;
        if (index == items.length) {
          return showAll
              ? _buildListFooter(hasMore, items.length, loadingMore)
              : _buildNeighborhoodFooter(items.length);
        }
        final household = items[index];
        return NeighborhoodHouseholdCard(
          key: ValueKey('area-${household.id}'),
          household: household,
          onPrayToggle: () => controller.togglePray(household),
          onUpdated: controller.updateHousehold,
        );
      },
    );
  }

  /// Under the neighborhood: what it is, and the way to see beyond it.
  Widget _buildNeighborhoodFooter(int shown) {
    final inRange = controller.areaComplete.value
        ? '${controller.areaHouseholds.length}'
        : '${controller.areaHouseholds.length}+';
    return Padding(
      key: const ValueKey('list-footer'),
      padding: EdgeInsets.symmetric(vertical: 8.h),
      child: Column(
        children: [
          Text(
            controller.isTemporary.value
                ? 'The nearest $shown homes to the place you searched.'
                : 'These $shown homes are your neighborhood: the same homes '
                      'as Home and your Prayer List. Change the number on '
                      'Home or in Profile \u203a Prayer preferences.',
            textAlign: TextAlign.center,
            style: AppTypography.body(
              color: AppColors.textSecondary,
              fontSize: 12.sp,
            ),
          ),
          if (controller.hasMoreInRange)
            TextButton(
              key: const ValueKey('browse-all'),
              onPressed: () => controller.setShowAllInRange(true),
              child: Text(
                'Browse all $inRange in range',
                style: AppTypography.label(
                  color: AppColors.primaryNavy,
                  fontSize: 13.sp,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildAllInRangeNote(int neighborhoodSize) {
    return Container(
      key: const ValueKey('all-in-range-note'),
      padding: EdgeInsets.all(12.r),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(12.r),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Only the nearest $neighborhoodSize are your neighborhood. '
            'Prayers for homes further out are saved, but do not count '
            'toward your daily goal.',
            style: AppTypography.body(
              color: AppColors.textSecondary,
              fontSize: 12.sp,
            ),
          ),
          TextButton(
            key: const ValueKey('back-to-neighborhood'),
            style: TextButton.styleFrom(padding: EdgeInsets.zero),
            onPressed: () => controller.setShowAllInRange(false),
            child: Text(
              'Show only my neighborhood',
              style: AppTypography.label(
                color: AppColors.primaryNavy,
                fontSize: 13.sp,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildListFooter(bool hasMore, int shown, bool loadingMore) {
    return Padding(
      key: const ValueKey('list-footer'),
      padding: EdgeInsets.symmetric(vertical: 8.h),
      child: Center(
        child: loadingMore && shown >= controller.areaHouseholds.length
            ? Row(
                key: const ValueKey('loading-more'),
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 18.r,
                    height: 18.r,
                    child: const CircularProgressIndicator(strokeWidth: 2.2),
                  ),
                  SizedBox(width: 10.w),
                  Text(
                    'Looking further out\u2026',
                    style: AppTypography.body(
                      color: AppColors.textSecondary,
                      fontSize: 12.sp,
                    ),
                  ),
                ],
              )
            : hasMore
            ? TextButton(
                onPressed: controller.loadMore,
                child: Text(
                  'Load more',
                  style: AppTypography.label(
                    color: AppColors.primaryNavy,
                    fontSize: 13.sp,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              )
            : Text(
                'All $shown households shown',
                style: AppTypography.body(
                  color: AppColors.textSecondary,
                  fontSize: 12.sp,
                ),
              ),
      ),
    );
  }

  Widget _buildMapCard(BuildContext context) {
    return Container(
      height: 300.h,
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Obx(() {
        final lat = controller.centerLatitude.value;
        final lng = controller.centerLongitude.value;

        return Stack(
          children: [
            if (lat != null && lng != null)
              Positioned.fill(
                child: HouseholdOsmMap(
                  centerLatitude: lat,
                  centerLongitude: lng,
                  households: controller.households.toList(),
                  areaMeters: controller.rangeMeters.value,
                  handle: controller.mapHandle,
                  initZoom: 17,
                  onHouseholdTap: (household) {
                    controller.selectHousehold(household);
                    HouseholdDetailBottomSheet.show(
                      context,
                      household: household,
                      onPrayToggle: () => controller.togglePray(household),
                      onUpdated: controller.updateHousehold,
                    );
                  },
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

            // Floating Radius Tag (Top Left)
            Positioned(
              top: 12.h,
              left: 12.w,
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 6.h),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8.r),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.radar_rounded,
                      size: 14.r,
                      color: AppColors.primaryNavy,
                    ),
                    SizedBox(width: 5.w),
                    Text(
                      // The subtitle already gives the range; say what the
                      // pins are.
                      'Nearest ${controller.households.length} on the map',
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

            // Zoom Controls (+ / -) (Top Right)
            if (lat != null && lng != null)
              Positioned(
                top: 12.h,
                right: 12.w,
                child: Column(
                  children: [
                    _buildZoomButton(
                      icon: Icons.add_rounded,
                      onTap: controller.zoomIn,
                    ),
                    SizedBox(height: 6.h),
                    _buildZoomButton(
                      icon: Icons.remove_rounded,
                      onTap: controller.zoomOut,
                    ),
                  ],
                ),
              ),
          ],
        );
      }),
    );
  }

  Widget _buildZoomButton({
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 30.r,
        height: 30.r,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(6.r),
          border: Border.all(color: const Color(0xFFE2E8F0)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Icon(icon, size: 18.r, color: AppColors.primaryNavy),
      ),
    );
  }
}
