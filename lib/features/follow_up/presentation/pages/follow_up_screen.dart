import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:gps_cielo/core/constants/app_colors.dart';
import 'package:gps_cielo/core/constants/app_typography.dart';
import 'package:gps_cielo/features/follow_up/presentation/controllers/follow_up_controller.dart';
import 'package:gps_cielo/features/follow_up/presentation/widgets/follow_up_household_item.dart';
import 'package:gps_cielo/shared/widgets/layout/collapsing_header_scroll_view.dart';

class FollowUpScreen extends GetView<FollowUpController> {
  const FollowUpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      // Loads the next page from Firestore shortly before the end.
      body: NotificationListener<ScrollUpdateNotification>(
        onNotification: (notification) {
          if (notification.depth == 0 &&
              notification.metrics.axis == Axis.vertical &&
              notification.metrics.extentAfter < 400) {
            controller.loadMore();
          }
          return false;
        },
        child: CollapsingHeaderScrollView(
          title: 'Follow-up',
          onRefresh: controller.loadFollowUps,
          subtitle: const Text(
            'Everyone you have prayed for, visited or invited',
          ),
          header: Row(
            children: [
              _legendDot(const Color(0xFF2E7D32), 'Prayed'),
              SizedBox(width: 14.w),
              _legendDot(const Color(0xFFD97706), 'Follow-up'),
              SizedBox(width: 14.w),
              _legendDot(const Color(0xFF1E88E5), 'Invited'),
            ],
          ),
          // The tabs stick below the top bar while the list scrolls.
          pinnedHeight: 48.h,
          pinnedColor: const Color(0xFFF8FAFC),
          pinned: _buildTabs(),
          slivers: [
            SliverPadding(
              padding: EdgeInsets.fromLTRB(16.w, 14.h, 16.w, 14.h),
              sliver: SliverToBoxAdapter(child: _buildSearch()),
            ),
            SliverPadding(
              padding: EdgeInsets.symmetric(horizontal: 16.w),
              sliver: Obx(() {
                final list = controller.filteredHouseholds;
                if (list.isEmpty && controller.isLoadingFirst.value) {
                  return SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 40.h),
                      child: const Center(child: CircularProgressIndicator()),
                    ),
                  );
                }
                if (list.isEmpty && controller.loadError.value != null) {
                  return SliverToBoxAdapter(child: _buildError());
                }
                if (list.isEmpty && !controller.hasMore.value) {
                  return SliverToBoxAdapter(child: _buildEmpty());
                }
                return SliverList.separated(
                  itemCount: list.length,
                  separatorBuilder: (context, _) => SizedBox(height: 12.h),
                  itemBuilder: (context, index) {
                    final item = list[index];
                    return FollowUpHouseholdItem(
                      key: ValueKey('follow-up-${item.id}'),
                      item: item,
                      selectedTab: controller.selectedTab.value,
                      nearHome: controller.isNearHome(item),
                      onUpdated: controller.updateHousehold,
                    );
                  },
                );
              }),
            ),
            SliverToBoxAdapter(child: Obx(_buildFooter)),
          ],
        ),
      ),
    );
  }

  /// Below the list: loading the next page, a retry, or the end.
  Widget _buildFooter() {
    final shown = controller.filteredHouseholds.length;
    final Widget child;
    if (controller.isLoadingMore.value) {
      child = Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 16.r,
            height: 16.r,
            child: const CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 10.w),
          Text(
            'Loading more…',
            style: AppTypography.body(
              color: AppColors.textSecondary,
              fontSize: 12.5.sp,
            ),
          ),
        ],
      );
    } else if (controller.loadError.value != null && shown > 0) {
      child = TextButton(
        onPressed: controller.loadMore,
        child: const Text('Could not load more. Tap to retry'),
      );
    } else if (controller.hasMore.value) {
      child = TextButton(
        key: const ValueKey('follow-up-load-more'),
        onPressed: controller.loadMore,
        child: Text(
          'Load more',
          style: AppTypography.label(
            color: AppColors.primaryNavy,
            fontSize: 13.sp,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
    } else if (shown > 0) {
      child = Text(
        "You're all caught up · $shown shown",
        key: const ValueKey('follow-up-end'),
        style: AppTypography.body(
          color: AppColors.textSecondary,
          fontSize: 12.sp,
        ),
      );
    } else {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 16.h),
      child: Center(child: child),
    );
  }

  Widget _buildError() {
    return Padding(
      padding: EdgeInsets.only(top: 8.h),
      child: AppNoticeCard(
        icon: Icons.cloud_off_rounded,
        title: 'Could not load your households',
        message: controller.loadError.value ?? '',
        actions: [
          OutlinedButton(
            onPressed: controller.loadFirstPage,
            child: const Text('Try again'),
          ),
        ],
      ),
    );
  }

  Widget _buildTabs() {
    return DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
      ),
      child: Obx(
        () => ListView(
          scrollDirection: Axis.horizontal,
          padding: EdgeInsets.symmetric(horizontal: 12.w),
          children: [
            for (final tab in FollowUpTab.values)
              _buildTab(tab, controller.countFor(tab)),
          ],
        ),
      ),
    );
  }

  Widget _buildTab(FollowUpTab tab, int count) {
    final isSelected = controller.selectedTab.value == tab;
    return InkWell(
      key: ValueKey('follow-up-tab-${tab.name}'),
      onTap: () => controller.selectTab(tab),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: EdgeInsets.symmetric(horizontal: 12.w),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: isSelected ? AppColors.primaryNavy : Colors.transparent,
              width: 2.5,
            ),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              tab.label,
              style: TextStyle(
                color: isSelected
                    ? AppColors.primaryNavy
                    : const Color(0xFF64748B),
                fontSize: 13.5.sp,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
            SizedBox(width: 6.w),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 1.h),
              decoration: BoxDecoration(
                color: isSelected
                    ? AppColors.primaryNavy
                    : const Color(0xFFE2E8F0),
                borderRadius: BorderRadius.circular(10.r),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  color: isSelected ? Colors.white : const Color(0xFF475569),
                  fontSize: 10.5.sp,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearch() {
    return Container(
      height: 46.h,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(color: AppColors.border),
      ),
      padding: EdgeInsets.symmetric(horizontal: 14.w),
      child: Row(
        children: [
          Icon(
            Icons.search_rounded,
            size: 20.r,
            color: const Color(0xFF94A3B8),
          ),
          SizedBox(width: 10.w),
          Expanded(
            child: TextField(
              onChanged: controller.updateSearch,
              textInputAction: TextInputAction.search,
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 13.5.sp,
                fontWeight: FontWeight.w500,
              ),
              decoration: const InputDecoration(
                hintText: 'Search by name, address or notes...',
                hintStyle: TextStyle(color: Color(0xFF94A3B8)),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    final searching = controller.searchQuery.value.trim().isNotEmpty;
    final none = controller.allHouseholds.isEmpty;
    return Padding(
      padding: EdgeInsets.only(top: 8.h),
      child: AppNoticeCard(
        icon: searching ? Icons.search_off_rounded : Icons.inbox_outlined,
        title: searching
            ? 'No matches'
            : none
            ? 'Nothing to follow up yet'
            : 'No households in this tab',
        message: searching
            ? 'No household matches "${controller.searchQuery.value.trim()}".'
            : none
            ? 'Households you pray for, visit or invite (from Home, '
                  'Neighborhood or your Prayer List) appear here.'
            : 'Try another tab, or All.',
      ),
    );
  }

  Widget _legendDot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8.r,
          height: 8.r,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        SizedBox(width: 5.w),
        Text(
          label,
          style: AppTypography.body(
            color: AppColors.textWhite.withValues(alpha: 0.85),
            fontSize: 11.5.sp,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
