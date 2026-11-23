import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:get/get.dart';
import 'package:gps_cielo/core/constants/app_assets.dart';
import 'package:gps_cielo/core/constants/app_colors.dart';
import 'package:gps_cielo/core/constants/app_strings.dart';
import 'package:gps_cielo/core/constants/app_typography.dart';
import 'package:gps_cielo/core/models/household_model.dart';
import 'package:gps_cielo/features/home/presentation/controllers/home_controller.dart';
import 'package:gps_cielo/features/main_nav/presentation/controllers/main_nav_controller.dart';
import 'package:gps_cielo/features/main_nav/presentation/models/main_nav_destination.dart';
import 'package:gps_cielo/features/profile/presentation/widgets/change_home_address.dart';
import 'package:gps_cielo/routes/app_routes.dart';
import 'package:gps_cielo/shared/widgets/bottom_sheets/household_detail_bottom_sheet.dart';
import 'package:gps_cielo/shared/widgets/household/household_row.dart';
import 'package:gps_cielo/shared/widgets/household/today_neighbors_card.dart';
import 'package:gps_cielo/shared/widgets/layout/collapsing_header_scroll_view.dart';
import 'package:gps_cielo/shared/widgets/map/household_osm_map.dart';

class HomeScreen extends GetView<HomeController> {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: RefreshIndicator(
        onRefresh: controller.reload,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            // Floating & Blending App Bar with reduced height & compact margins
            // The logo and notifications stay pinned; everything else scrolls.
            SliverAppBar(
              pinned: true,
              elevation: 0,
              scrolledUnderElevation: 3,
              shadowColor: Colors.black.withValues(alpha: 0.12),
              backgroundColor: AppColors.surface,
              surfaceTintColor: Colors.transparent,
              automaticallyImplyLeading: false,
              toolbarHeight: 62.h,
              titleSpacing: 16.w,
              title: Row(
                children: [
                  SvgPicture.asset(
                    AppAssets.logoMark,
                    width: 32.w,
                    height: 38.h,
                    fit: BoxFit.contain,
                  ),
                  SizedBox(width: 10.w),
                  // Shrinks (never overflows) on narrow phones / big text.
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              Text(
                                'GPS ',
                                style: AppTypography.heading(
                                  color: AppColors.primaryNavy,
                                  fontSize: 16.sp,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              Text(
                                'PARA EL ',
                                style: AppTypography.heading(
                                  color: AppColors.primaryGold,
                                  fontSize: 10.sp,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                          Text(
                            'CIELO',
                            style: AppTypography.heading(
                              color: AppColors.primaryNavy,
                              fontSize: 16.sp,
                              fontWeight: FontWeight.w900,
                              height: 0.9,
                            ),
                          ),
                          Text(
                            AppStrings.appTagline,
                            style: AppTypography.body(
                              color: AppColors.textSecondary,
                              fontSize: 9.5.sp,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              actions: [
                Padding(
                  padding: EdgeInsets.only(right: 16.w),
                  child: Obx(
                    () => HeaderIconButton(
                      key: const ValueKey('home-notifications'),
                      icon: Icons.notifications_none_rounded,
                      tooltip: 'Notifications',
                      dark: false,
                      badge: controller.notificationCount.value,
                      onPressed: () => Get.toNamed(AppRoutes.notifications),
                    ),
                  ),
                ),
              ],
              bottom: const PreferredSize(
                preferredSize: Size.fromHeight(1.0),
                child: Divider(color: AppColors.border, height: 1),
              ),
            ),

            SliverPadding(
              padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 28.h),
              sliver: SliverToBoxAdapter(child: Obx(() => _buildBody(context))),
            ),
          ],
        ),
      ),
    );
  }

  static void _goTo(MainNavDestination destination) {
    if (Get.isRegistered<MainNavController>()) {
      Get.find<MainNavController>().changeDestination(destination);
    }
  }

  Widget _buildBody(BuildContext context) {
    final plan = controller.plan.value;
    final homes = controller.neighborhood;
    final name = controller.firstName.value;
    final greeting = HomeController.greeting(DateTime.now());

    final Widget content;
    if (!controller.hasHome.value) {
      content = AppNoticeCard(
        icon: Icons.home_outlined,
        title: 'Set your home address',
        message:
            'Your neighborhood is the homes nearest your home. Add your '
            'address to meet your neighbors.',
        actions: [ChangeHomeAddress.button()],
      );
    } else if (homes.isEmpty && controller.isLoading.value) {
      content = Padding(
        padding: EdgeInsets.symmetric(vertical: 40.h),
        child: Column(
          children: [
            const CircularProgressIndicator(),
            SizedBox(height: 12.h),
            Text(
              'Finding your neighbors...',
              style: AppTypography.body(
                color: AppColors.textSecondary,
                fontSize: 13.sp,
              ),
            ),
          ],
        ),
      );
    } else if (homes.isEmpty && controller.homeUnavailable.value) {
      content = _AreaUnavailableCard(
        key: const ValueKey('home-unavailable'),
        reason: controller.homeNote.value,
      );
    } else if (homes.isEmpty) {
      content = AppNoticeCard(
        icon: Icons.travel_explore_rounded,
        title: 'No households near your home yet',
        message: 'Try changing your home address.',
        actions: [ChangeHomeAddress.button()],
      );
    } else {
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TodayNeighborsCard(
            plan: plan,
            onTap: () => _goTo(MainNavDestination.prayerList),
          ),
          SizedBox(height: 16.h),
          _buildNeighborhoodCard(homes),
          SizedBox(height: 22.h),
          _buildTodayHeader(),
          SizedBox(height: 10.h),
          if (plan.isCycleComplete)
            AppNoticeCard(
              key: const ValueKey('home-round-complete'),
              icon: Icons.celebration_rounded,
              highlight: true,
              title: 'Round complete!',
              message:
                  'You prayed for all ${plan.cycleTotal} neighbors. A new '
                  'round starts at midnight, or start it now on the Prayer '
                  'List.',
            )
          else
            for (final household in plan.today) ...[
              _row(context, household),
              SizedBox(height: 10.h),
            ],
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          name.isEmpty ? greeting : '$greeting, $name',
          key: const ValueKey('home-greeting'),
          style: AppTypography.heading(
            color: AppColors.textPrimary,
            fontSize: 22.sp,
            fontWeight: FontWeight.w800,
          ),
        ),
        SizedBox(height: 2.h),
        Text(
          'Who will you pray for today?',
          style: AppTypography.body(
            color: AppColors.textSecondary,
            fontSize: 13.sp,
          ),
        ),
        SizedBox(height: 16.h),
        content,
      ],
    );
  }

  Widget _row(BuildContext context, HouseholdModel household) {
    void pray() => controller.togglePray(household);
    return HouseholdRow(
      key: ValueKey('home-today-${household.id}'),
      household: household,
      onPrayToggle: pray,
      onTap: () => HouseholdDetailBottomSheet.show(
        context,
        household: household,
        onPrayToggle: pray,
        onUpdated: controller.updateHousehold,
      ),
    );
  }

  Widget _buildTodayHeader() {
    return Row(
      children: [
        Expanded(
          child: Text(
            'Pray for today',
            style: AppTypography.heading(
              color: AppColors.textPrimary,
              fontSize: 16.sp,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        _linkButton(
          'Prayer List',
          key: const ValueKey('home-prayer-list'),
          onTap: () => _goTo(MainNavDestination.prayerList),
        ),
      ],
    );
  }

  Widget _linkButton(String label, {required VoidCallback onTap, Key? key}) {
    return InkWell(
      key: key,
      onTap: onTap,
      borderRadius: BorderRadius.circular(8.r),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 4.w, vertical: 6.h),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: AppTypography.label(
                color: AppColors.primaryNavy,
                fontSize: 13.sp,
                fontWeight: FontWeight.w700,
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              size: 18.r,
              color: AppColors.primaryNavy,
            ),
          ],
        ),
      ),
    );
  }

  /// Small, still map of the neighborhood; taps open the Neighborhood tab.
  Widget _buildNeighborhoodCard(List<HouseholdModel> homes) {
    final lat = controller.homeLatitude.value;
    final lng = controller.homeLongitude.value;
    final count = homes.length;
    final prayed = homes.where((h) => h.isPrayed).length;
    void open() => _goTo(MainNavDestination.neighborhood);
    return Container(
      key: const ValueKey('home-neighborhood-card'),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18.r),
        border: Border.all(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(14.w, 10.h, 6.w, 6.h),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'My neighborhood',
                        style: AppTypography.heading(
                          color: AppColors.textPrimary,
                          fontSize: 15.sp,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        '$prayed of $count prayed this round',
                        style: AppTypography.body(
                          color: AppColors.textSecondary,
                          fontSize: 11.5.sp,
                        ),
                      ),
                      if (controller.homeNote.value case final note?)
                        Text(
                          note,
                          key: const ValueKey('home-source-note'),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.body(
                            color: AppColors.textSecondary,
                            fontSize: 10.5.sp,
                          ),
                        ),
                    ],
                  ),
                ),
                _linkButton(
                  'View all $count',
                  key: const ValueKey('home-view-all'),
                  onTap: open,
                ),
              ],
            ),
          ),
          SizedBox(
            height: 160.h,
            child: Stack(
              children: [
                if (lat != null && lng != null)
                  Positioned.fill(
                    child: HouseholdOsmMap(
                      centerLatitude: lat,
                      centerLongitude: lng,
                      households: homes,
                      interactive: false,
                      markerSize: 22,
                    ),
                  ),
                Positioned(
                  left: 10.w,
                  top: 10.h,
                  child: _MapChip(text: 'Nearest $count homes'),
                ),
                // The map is still; a tap anywhere opens Neighborhood.
                Positioned.fill(
                  child: GestureDetector(
                    key: const ValueKey('home-map-tap'),
                    behavior: HitTestBehavior.translucent,
                    onTap: open,
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

/// White pill over a map ("Nearest 50 homes").
class _MapChip extends StatelessWidget {
  const _MapChip({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 5.h),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20.r),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 6),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.home_rounded, size: 13.r, color: AppColors.primaryNavy),
          SizedBox(width: 4.w),
          Text(
            text,
            style: AppTypography.label(
              color: AppColors.primaryNavy,
              fontSize: 11.sp,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// Figma 4.5: the saved home is outside the loaded states.
class _AreaUnavailableCard extends StatelessWidget {
  const _AreaUnavailableCard({super.key, this.reason});

  /// Why the area is empty (Melissa only), instead of the general text.
  final String? reason;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(20.r),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18.r),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Container(
            width: 56.r,
            height: 56.r,
            decoration: BoxDecoration(
              color: AppColors.primaryNavy.withValues(alpha: 0.07),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.travel_explore_rounded,
              size: 28.r,
              color: AppColors.primaryNavy,
            ),
          ),
          SizedBox(height: 12.h),
          Text(
            AppStrings.areaUnavailable,
            textAlign: TextAlign.center,
            style: AppTypography.heading(
              color: AppColors.textPrimary,
              fontSize: 17.sp,
              fontWeight: FontWeight.w800,
            ),
          ),
          SizedBox(height: 6.h),
          Text(
            reason ??
                "We don't have household data around your home yet. "
                    '${AppStrings.areaComingSoon}',
            textAlign: TextAlign.center,
            style: AppTypography.body(
              color: AppColors.textSecondary,
              fontSize: 13.sp,
              height: 1.4,
            ),
          ),
          // The Overture coverage pill does not apply to owner records.
          if (reason == null) ...[
            SizedBox(height: 10.h),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
              decoration: BoxDecoration(
                color: prayedGreenLight,
                borderRadius: BorderRadius.circular(20.r),
              ),
              child: Text(
                AppStrings.areasAvailable,
                style: AppTypography.label(
                  color: prayedGreen,
                  fontSize: 12.sp,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
          SizedBox(height: 14.h),
          ChangeHomeAddress.button(),
        ],
      ),
    );
  }
}
