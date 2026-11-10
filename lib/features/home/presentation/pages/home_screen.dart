import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:get/get.dart';
import 'package:gps_cielo/core/constants/app_assets.dart';
import 'package:gps_cielo/core/constants/app_colors.dart';
import 'package:gps_cielo/core/constants/app_strings.dart';
import 'package:gps_cielo/core/constants/app_typography.dart';
import 'package:gps_cielo/core/utils/search_range.dart';
import 'package:gps_cielo/features/home/presentation/controllers/home_controller.dart';
import 'package:gps_cielo/features/home/presentation/widgets/household_card.dart';
import 'package:gps_cielo/shared/widgets/bottom_sheets/household_detail_bottom_sheet.dart';
import 'package:gps_cielo/features/home/presentation/widgets/radius_map_card.dart';
import 'package:gps_cielo/features/main_nav/presentation/controllers/main_nav_controller.dart';
import 'package:gps_cielo/features/main_nav/presentation/models/main_nav_destination.dart';
import 'package:gps_cielo/routes/app_routes.dart';
import 'package:gps_cielo/shared/widgets/buttons/app_primary_button.dart';
import 'package:gps_cielo/shared/widgets/inputs/app_search_field.dart';
import 'package:gps_cielo/shared/widgets/dialogs/app_confirmation_dialog.dart';
import 'package:gps_cielo/shared/widgets/layout/collapsing_header_scroll_view.dart';

class HomeScreen extends GetView<HomeController> {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
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
                Column(
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

          // Main Scrollable Body with reduced top margin
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(16.w, 10.h, 16.w, 16.h),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Address Search Card
                  Container(
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
                            Icon(
                              Icons.location_on_outlined,
                              size: 18.r,
                              color: AppColors.primaryNavy,
                            ),
                            SizedBox(width: 8.w),
                            Text(
                              AppStrings.enterAddress,
                              style: AppTypography.heading(
                                color: AppColors.textPrimary,
                                fontSize: 14.sp,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 12.h),
                        Obx(
                          () => AppSearchField(
                            controller: controller.searchAddressController,
                            nearLatitude: controller.nearLatitude.value,
                            nearLongitude: controller.nearLongitude.value,
                            onAddressSelected: controller.selectSuggestion,
                            onSubmitted: (_) => controller.searchNeighborhood(),
                            onGpsPressed: controller.useCurrentLocation,
                            isLocating: controller.isLocating.value,
                          ),
                        ),
                        SizedBox(height: 12.h),
                        Obx(
                          () => AppPrimaryButton(
                            key: const ValueKey('search-neighborhood-button'),
                            label: AppStrings.searchNeighborhood,
                            icon: const Icon(
                              Icons.search_rounded,
                              size: 18,
                              color: Colors.white,
                            ),
                            height: 48,
                            isLoading: controller.isSearching.value,
                            onPressed: () => controller.searchNeighborhood(),
                          ),
                        ),
                        SizedBox(height: 10.h),
                        Obx(() => _buildSearchStatus(context)),
                        Center(
                          child: Text(
                            AppStrings.searchHint,
                            style: AppTypography.body(
                              color: AppColors.textSecondary,
                              fontSize: 12.sp,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  SizedBox(height: 16.h),

                  // Radius Map Card
                  Obx(
                    () => RadiusMapCard(
                      radiusHomes: controller.radiusHomes.value,
                      radiusOptions: HomeController.radiusOptions,
                      rangeMeters: controller.rangeMeters.value,
                      onRadiusChanged: controller.changeRadius,
                      defaultRadius: controller.defaultRadius.value,
                      isRadiusFiltered: controller.isRadiusFiltered.value,
                      onResetRadius: controller.resetRadius,
                      households: controller.nearbyHouseholds.toList(),
                      centerLatitude: controller.centerLatitude.value,
                      centerLongitude: controller.centerLongitude.value,
                      centerLabel: controller.centerLabel.value,
                      isTemporary: controller.isTemporarySearch.value,
                      isLoading: controller.isLoading.value,
                      foundInRange: controller.foundInRange.value,
                      rangeComplete: controller.areaComplete.value,
                      onHouseholdTap: (household) =>
                          HouseholdDetailBottomSheet.show(
                            context,
                            household: household,
                            onPrayToggle: () =>
                                controller.togglePray(household),
                            onUpdated: controller.updateHousehold,
                          ),
                      onExpand: () {
                        if (Get.isRegistered<MainNavController>()) {
                          Get.find<MainNavController>().changeDestination(
                            MainNavDestination.neighborhood,
                          );
                        }
                      },
                    ),
                  ),

                  SizedBox(height: 20.h),

                  // Nearby Households Header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.people_outline_rounded,
                                size: 18.r,
                                color: AppColors.primaryNavy,
                              ),
                              SizedBox(width: 6.w),
                              Obx(
                                () => Text(
                                  '${AppStrings.nearbyHouseholds}(${controller.nearbyHouseholds.length})',
                                  style: AppTypography.heading(
                                    color: AppColors.textPrimary,
                                    fontSize: 16.sp,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          Text(
                            'Nearest first',
                            style: AppTypography.body(
                              color: AppColors.textSecondary,
                              fontSize: 12.sp,
                            ),
                          ),
                        ],
                      ),
                      TextButton.icon(
                        onPressed: () {
                          if (Get.isRegistered<MainNavController>()) {
                            Get.find<MainNavController>().changeDestination(
                              MainNavDestination.neighborhood,
                            );
                          }
                        },
                        icon: Icon(
                          Icons.map_outlined,
                          size: 16.r,
                          color: AppColors.primaryNavy,
                        ),
                        label: Text(
                          AppStrings.viewOnMap,
                          style: AppTypography.label(
                            color: AppColors.primaryNavy,
                            fontSize: 13.sp,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),

                  SizedBox(height: 12.h),

                  // Household List Card Container
                  Container(
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(16.r),
                      border: Border.all(color: AppColors.border),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Obx(
                      () => controller.nearbyHouseholds.isEmpty
                          ? _buildEmptyList()
                          : Column(
                              children: [
                                ListView.separated(
                                  padding: EdgeInsets.zero,
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  itemCount:
                                      controller.nearbyHouseholds.length > 5
                                      ? 5
                                      : controller.nearbyHouseholds.length,
                                  separatorBuilder: (context, _) =>
                                      const Divider(
                                        color: AppColors.border,
                                        height: 1,
                                      ),
                                  itemBuilder: (context, index) {
                                    final household =
                                        controller.nearbyHouseholds[index];
                                    return HouseholdCard(
                                      household: household,
                                      onPrayToggle: () =>
                                          controller.togglePray(household),
                                      onTap: () {
                                        HouseholdDetailBottomSheet.show(
                                          context,
                                          household: household,
                                          onPrayToggle: () =>
                                              controller.togglePray(household),
                                          onUpdated: (updated) => controller
                                              .updateHousehold(updated),
                                        );
                                      },
                                    );
                                  },
                                ),
                                const Divider(
                                  color: AppColors.border,
                                  height: 1,
                                ),
                                InkWell(
                                  onTap: () {
                                    if (Get.isRegistered<MainNavController>()) {
                                      Get.find<MainNavController>()
                                          .changeDestination(
                                            MainNavDestination.neighborhood,
                                          );
                                    }
                                  },
                                  child: Container(
                                    padding: EdgeInsets.symmetric(
                                      vertical: 14.h,
                                    ),
                                    alignment: Alignment.center,
                                    child: Text(
                                      '${AppStrings.viewAllHouseholds} (${controller.nearbyHouseholds.length})',
                                      style: AppTypography.label(
                                        color: AppColors.primaryNavy,
                                        fontSize: 13.sp,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),

                  SizedBox(height: 24.h),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Tells the user which location the households below are near. While a
  /// searched place is shown, offers to go back home or make it home.
  Widget _buildSearchStatus(BuildContext context) {
    if (controller.isTemporarySearch.value) {
      return _buildViewingBanner(context);
    }
    final text = controller.hasSearchCenter.value
        ? 'Showing homes near your home address.'
        : 'Search a place or use your current location to find households.';
    return Padding(
      padding: EdgeInsets.only(bottom: 6.h),
      child: Row(
        children: [
          Icon(Icons.home_outlined, size: 16.r, color: AppColors.textSecondary),
          SizedBox(width: 6.w),
          Expanded(
            child: Text(
              text,
              key: const ValueKey('home-search-status'),
              style: AppTypography.body(
                color: AppColors.textSecondary,
                fontSize: 12.sp,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildViewingBanner(BuildContext context) {
    final place = controller.centerLabel.value;
    return Container(
      key: const ValueKey('viewing-banner'),
      width: double.infinity,
      margin: EdgeInsets.only(bottom: 8.h),
      padding: EdgeInsets.fromLTRB(12.w, 10.h, 12.w, 8.h),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F3FF),
        borderRadius: BorderRadius.circular(12.r),
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
                      'Viewing $place',
                      key: const ValueKey('home-search-status'),
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
                      'Just looking around: your home address and Prayer '
                      'List are unchanged. Prayers and visits here are '
                      'still saved to Follow-up.',
                      style: AppTypography.body(
                        color: AppColors.textSecondary,
                        fontSize: 11.5.sp,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: 6.h),
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
                  textStyle: AppTypography.label(
                    fontSize: 12.5.sp,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Obx(
                () => TextButton.icon(
                  key: const ValueKey('set-as-home'),
                  onPressed: controller.isSavingHome.value
                      ? null
                      : () => _confirmSetAsHome(place),
                  icon: controller.isSavingHome.value
                      ? SizedBox(
                          width: 14.r,
                          height: 14.r,
                          child: const CircularProgressIndicator(
                            strokeWidth: 2,
                          ),
                        )
                      : Icon(Icons.push_pin_outlined, size: 16.r),
                  label: const Text('Set as my home'),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF7C3AED),
                    textStyle: AppTypography.label(
                      fontSize: 12.5.sp,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _confirmSetAsHome(String place) {
    AppConfirmationDialog.show(
      title: 'Set as your home?',
      message:
          'Your home address will change to "$place". Your Prayer '
          'List, Neighborhood and Home will use the households near it.',
      confirmLabel: 'Set as home',
      onConfirm: controller.setSearchedPlaceAsHome,
    );
  }

  Widget _buildEmptyList() {
    final loading = controller.isLoading.value;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 24.h),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (loading) ...[
            SizedBox(
              width: 16.r,
              height: 16.r,
              child: const CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 10.w),
          ],
          Flexible(
            child: Text(
              loading
                  ? 'Finding nearby households...'
                  : controller.hasSearchCenter.value
                  ? 'No households within '
                        '${SearchRange.formatDistance(controller.rangeMeters.value ?? 0)} '
                        'of this location yet. Try another place or a '
                        'larger search range in Settings.'
                  : 'No location selected yet.',
              textAlign: TextAlign.center,
              style: AppTypography.body(
                color: AppColors.textSecondary,
                fontSize: 13.sp,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
