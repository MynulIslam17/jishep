import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:gps_cielo/core/constants/app_colors.dart';
import 'package:gps_cielo/core/constants/app_typography.dart';
import 'package:gps_cielo/features/neighborhood/presentation/controllers/neighborhood_controller.dart';
import 'package:gps_cielo/features/neighborhood/presentation/widgets/neighborhood_household_card.dart';
import 'package:gps_cielo/features/neighborhood/presentation/widgets/neighborhood_map_painter.dart';
import 'package:gps_cielo/shared/widgets/bottom_sheets/household_detail_bottom_sheet.dart';

class NeighborhoodScreen extends GetView<NeighborhoodController> {
  const NeighborhoodScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        slivers: [
          // Pinned Top Navy Header with Title and Segmented Switcher
          SliverAppBar(
            pinned: true,
            floating: false,
            snap: false,
            elevation: 0,
            backgroundColor: AppColors.primaryNavy,
            surfaceTintColor: Colors.transparent,
            automaticallyImplyLeading: false,
            toolbarHeight: 116.h,
            titleSpacing: 0,
            title: Padding(
              padding: EdgeInsets.fromLTRB(20.w, 4.h, 20.w, 8.h),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'My Neighborhood',
                    style: AppTypography.heading(
                      color: AppColors.textWhite,
                      fontSize: 20.sp,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  SizedBox(height: 2.h),
                  Obx(
                    () => Text(
                      'Radius: ${controller.radiusHomes.value} homes',
                      style: AppTypography.body(
                        color: AppColors.textWhite.withValues(alpha: 0.75),
                        fontSize: 12.sp,
                      ),
                    ),
                  ),
                  SizedBox(height: 12.h),

                  // Map / List Segmented Switcher
                  Container(
                    height: 40.h,
                    padding: EdgeInsets.all(3.5.r),
                    decoration: BoxDecoration(
                      color: const Color(0xFF26375A),
                      borderRadius: BorderRadius.circular(10.r),
                    ),
                    child: Obx(
                      () => Row(
                        children: [
                          Expanded(
                            child: _buildSegmentButton(
                              label: 'Map',
                              isSelected: controller.viewMode.value ==
                                  NeighborhoodViewMode.map,
                              onTap: () => controller
                                  .switchViewMode(NeighborhoodViewMode.map),
                            ),
                          ),
                          Expanded(
                            child: _buildSegmentButton(
                              label: 'List',
                              isSelected: controller.viewMode.value ==
                                  NeighborhoodViewMode.list,
                              onTap: () => controller
                                  .switchViewMode(NeighborhoodViewMode.list),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Map Container Sliver: smoothly scrolls out of view on scroll up and reappears on scroll down
          Obx(() {
            if (controller.viewMode.value != NeighborhoodViewMode.map) {
              return const SliverToBoxAdapter(child: SizedBox.shrink());
            }

            return SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(16.w, 14.h, 16.w, 8.h),
                child: _buildMapCard(context),
              ),
            );
          }),

          // Subheader Info Sliver: "Households found: X" / "Updated 2 days ago"
          SliverToBoxAdapter(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding:
                      EdgeInsets.symmetric(horizontal: 20.w, vertical: 12.h),
                  color: AppColors.surface,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Obx(
                        () => Text(
                          'Households found: ${controller.households.length}',
                          style: AppTypography.heading(
                            color: AppColors.textPrimary,
                            fontSize: 14.sp,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Text(
                        'Updated 2 days ago',
                        style: AppTypography.body(
                          color: AppColors.textSecondary,
                          fontSize: 12.sp,
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(color: AppColors.border, height: 1),
              ],
            ),
          ),

          // Reactive Household List
          Obx(() {
            if (controller.isLoading.value) {
              return const SliverFillRemaining(
                child: Center(child: CircularProgressIndicator()),
              );
            }

            return SliverList.separated(
              itemCount: controller.households.length,
              separatorBuilder: (context, _) =>
                  const Divider(color: AppColors.border, height: 1),
              itemBuilder: (context, index) {
                final household = controller.households[index];
                return NeighborhoodHouseholdCard(
                  household: household,
                  onPrayToggle: () => controller.togglePray(household),
                  onUpdated: (updated) => controller.updateHousehold(updated),
                );
              },
            );
          }),

          // Bottom padding
          SliverToBoxAdapter(
            child: SizedBox(height: 24.h),
          ),
        ],
      ),
    );
  }

  Widget _buildSegmentButton({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(8.r),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.12),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ]
              : null,
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: AppTypography.label(
            color: isSelected
                ? AppColors.primaryNavy
                : AppColors.textWhite.withValues(alpha: 0.75),
            fontSize: 13.5.sp,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _buildMapCard(BuildContext context) {
    return Container(
      height: 240.h,
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          // City Map background with radial search overlay
          Positioned.fill(
            child: CustomPaint(
              painter: NeighborhoodMapPainter(
                radiusHomes: controller.radiusHomes.value,
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
                  Obx(
                    () => Text(
                      'Radius: ${controller.radiusHomes.value} homes',
                      style: AppTypography.label(
                        color: AppColors.primaryNavy,
                        fontSize: 11.5.sp,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Zoom Controls (+ / -) (Top Right)
          Positioned(
            top: 12.h,
            right: 12.w,
            child: Column(
              children: [
                _buildZoomButton(
                  icon: Icons.add_rounded,
                  onTap: () => controller.zoomIn(),
                ),
                SizedBox(height: 6.h),
                _buildZoomButton(
                  icon: Icons.remove_rounded,
                  onTap: () => controller.zoomOut(),
                ),
              ],
            ),
          ),

          // Interactive Map Pins
          ..._buildMapMarkers(context),
        ],
      ),
    );
  }

  List<Widget> _buildMapMarkers(BuildContext context) {
    final pinOffsets = [
      const Offset(0.32, 0.35),
      const Offset(0.68, 0.40),
      const Offset(0.55, 0.38),
      const Offset(0.52, 0.42),
      const Offset(0.42, 0.41),
      const Offset(0.48, 0.47),
      const Offset(0.58, 0.32),
      const Offset(0.40, 0.31),
      const Offset(0.38, 0.46),
      const Offset(0.62, 0.48),
    ];

    final widgets = <Widget>[];

    for (int i = 0;
        i < controller.households.length && i < pinOffsets.length;
        i++) {
      final household = controller.households[i];
      final offset = pinOffsets[i];

      widgets.add(
        Align(
          alignment: FractionalOffset(offset.dx, offset.dy),
          child: GestureDetector(
            onTap: () {
              controller.selectHousehold(household);
              HouseholdDetailBottomSheet.show(
                context,
                household: household,
                onPrayToggle: () => controller.togglePray(household),
                onUpdated: (updated) => controller.updateHousehold(updated),
              );
            },
            child: Icon(
              Icons.location_on_rounded,
              size: 22.r,
              color: AppColors.primaryNavy,
            ),
          ),
        ),
      );
    }

    return widgets;
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
        child: Icon(
          icon,
          size: 18.r,
          color: AppColors.primaryNavy,
        ),
      ),
    );
  }
}
