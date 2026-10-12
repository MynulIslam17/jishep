import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:gps_cielo/core/constants/app_colors.dart';
import 'package:gps_cielo/core/constants/app_typography.dart';
import 'package:gps_cielo/core/utils/app_system_insets.dart';
import 'package:gps_cielo/features/follow_up/presentation/controllers/follow_up_controller.dart';
import 'package:gps_cielo/features/follow_up/presentation/widgets/follow_up_household_item.dart';

class FollowUpScreen extends GetView<FollowUpController> {
  const FollowUpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final topInset = AppSystemInsets.top(context);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        slivers: [
          // 1. Top Navy Header Sliver: Scrolls away naturally on scroll down
          SliverToBoxAdapter(
            child: Container(
              width: double.infinity,
              padding: EdgeInsets.fromLTRB(20.w, topInset + 10.h, 20.w, 18.h),
              color: AppColors.primaryNavy,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title
                  Text(
                    'Follow-up',
                    style: AppTypography.heading(
                      color: AppColors.textWhite,
                      fontSize: 22.sp,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  SizedBox(height: 12.h),

                  // Status Legend (3 Color Dots Row)
                  Row(
                    children: [
                      _buildLegendDot(
                        color: const Color(0xFF2E7D32),
                        label: 'Prayed',
                      ),
                      SizedBox(width: 14.w),
                      _buildLegendDot(
                        color: const Color(0xFFD97706),
                        label: 'Follow-up',
                      ),
                      SizedBox(width: 14.w),
                      _buildLegendDot(
                        color: const Color(0xFF1E88E5),
                        label: 'Invited',
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // 2. Pinned Segmented Filter Tabs Bar Sliver: Remains Fixed at Top below Status Bar
          SliverPersistentHeader(
            pinned: true,
            delegate: _FollowUpTabsHeaderDelegate(
              tabHeight: 48.h,
              topInset: topInset,
              child: Container(
                width: double.infinity,
                decoration: const BoxDecoration(
                  color: Color(0xFFF8FAFC),
                  border: Border(
                    bottom: BorderSide(color: Color(0xFFE2E8F0), width: 1),
                  ),
                ),
                child: Obx(
                  () => SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    padding: EdgeInsets.symmetric(horizontal: 12.w),
                    child: Row(
                      children: FollowUpTab.values.map((tab) {
                        final isSelected = controller.selectedTab.value == tab;
                        return GestureDetector(
                          onTap: () => controller.selectTab(tab),
                          child: Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: 14.w,
                              vertical: 12.h,
                            ),
                            decoration: BoxDecoration(
                              border: Border(
                                bottom: BorderSide(
                                  color: isSelected
                                      ? AppColors.primaryNavy
                                      : Colors.transparent,
                                  width: 2.5,
                                ),
                              ),
                            ),
                            child: Text(
                              tab.label,
                              style: TextStyle(
                                color: isSelected
                                    ? AppColors.primaryNavy
                                    : const Color(0xFF64748B),
                                fontSize: 13.5.sp,
                                fontWeight: isSelected
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ),
            ),
          ),

          // 3. Search & Count Header Sliver
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(16.w, 14.h, 16.w, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Households Count Label
                  Obx(
                    () => Text(
                      '${controller.filteredHouseholds.length} households',
                      style: AppTypography.body(
                        color: const Color(0xFF64748B),
                        fontSize: 13.sp,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),

                  SizedBox(height: 10.h),

                  // Search Text Field
                  Container(
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
                            onChanged: (val) => controller.updateSearch(val),
                            style: TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 13.5.sp,
                              fontWeight: FontWeight.w500,
                            ),
                            decoration: const InputDecoration(
                              hintText: 'Search by name or address...',
                              hintStyle: TextStyle(
                                color: Color(0xFF94A3B8),
                              ),
                              border: InputBorder.none,
                              isDense: true,
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  SizedBox(height: 14.h),
                ],
              ),
            ),
          ),

          // 4. Household Cards List Sliver
          SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: 16.w),
            sliver: Obx(() {
              final list = controller.filteredHouseholds;
              if (list.isEmpty) {
                return SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 40.h),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.search_off_rounded,
                            size: 44.r,
                            color: const Color(0xFF94A3B8),
                          ),
                          SizedBox(height: 8.h),
                          Text(
                            'No households found in this filter',
                            style: TextStyle(
                              color: const Color(0xFF64748B),
                              fontSize: 13.5.sp,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }

              return SliverList.separated(
                itemCount: list.length,
                separatorBuilder: (context, _) => SizedBox(height: 12.h),
                itemBuilder: (context, index) {
                  final item = list[index];
                  return Obx(
                    () => FollowUpHouseholdItem(
                      item: item,
                      selectedTab: controller.selectedTab.value,
                      onUpdated: (updated) => controller.updateHousehold(updated),
                    ),
                  );
                },
              );
            }),
          ),

          // Bottom padding
          SliverToBoxAdapter(
            child: SizedBox(height: 24.h),
          ),
        ],
      ),
    );
  }

  Widget _buildLegendDot({required Color color, required String label}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8.r,
          height: 8.r,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        SizedBox(width: 5.w),
        Text(
          label,
          style: TextStyle(
            color: AppColors.textWhite.withValues(alpha: 0.85),
            fontSize: 11.5.sp,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _FollowUpTabsHeaderDelegate extends SliverPersistentHeaderDelegate {
  final Widget child;
  final double tabHeight;
  final double topInset;

  _FollowUpTabsHeaderDelegate({
    required this.child,
    required this.tabHeight,
    required this.topInset,
  });

  @override
  double get minExtent => tabHeight + topInset;

  @override
  double get maxExtent => tabHeight + topInset;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Container(
      color: const Color(0xFFF8FAFC),
      padding: EdgeInsets.only(top: topInset),
      height: tabHeight + topInset,
      child: child,
    );
  }

  @override
  bool shouldRebuild(_FollowUpTabsHeaderDelegate oldDelegate) {
    return oldDelegate.tabHeight != tabHeight ||
        oldDelegate.topInset != topInset ||
        oldDelegate.child != child;
  }
}
