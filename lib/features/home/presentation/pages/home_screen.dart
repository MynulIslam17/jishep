import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:get/get.dart';
import 'package:gps_cielo/core/constants/app_assets.dart';
import 'package:gps_cielo/core/constants/app_colors.dart';
import 'package:gps_cielo/core/constants/app_strings.dart';
import 'package:gps_cielo/core/constants/app_typography.dart';
import 'package:gps_cielo/features/home/presentation/controllers/home_controller.dart';
import 'package:gps_cielo/features/home/presentation/widgets/household_card.dart';
import 'package:gps_cielo/shared/widgets/bottom_sheets/household_detail_bottom_sheet.dart';
import 'package:gps_cielo/features/home/presentation/widgets/radius_map_card.dart';
import 'package:gps_cielo/features/main_nav/presentation/controllers/main_nav_controller.dart';
import 'package:gps_cielo/features/main_nav/presentation/models/main_nav_destination.dart';
import 'package:gps_cielo/routes/app_routes.dart';
import 'package:gps_cielo/shared/widgets/buttons/app_primary_button.dart';
import 'package:gps_cielo/shared/widgets/inputs/app_search_field.dart';

class HomeScreen extends GetView<HomeController> {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        slivers: [
          // Floating & Blending App Bar with reduced height & compact margins
          SliverAppBar(
            floating: true,
            snap: true,
            pinned: false,
            elevation: 1.0,
            shadowColor: Colors.black.withValues(alpha: 0.10),
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
                child: Center(
                  child: Stack(
                    children: [
                      Container(
                        width: 38.r,
                        height: 38.r,
                        decoration: const BoxDecoration(
                          color: AppColors.inputSurface,
                          shape: BoxShape.circle,
                        ),
                        child: IconButton(
                          padding: EdgeInsets.zero,
                          icon: Icon(
                            Icons.notifications_none_rounded,
                            size: 20.r,
                            color: AppColors.primaryNavy,
                          ),
                          onPressed: () => Get.toNamed(AppRoutes.notifications),
                        ),
                      ),
                      Obx(
                        () => controller.notificationCount.value > 0
                            ? Positioned(
                                top: 2,
                                right: 2,
                                child: Container(
                                  padding: EdgeInsets.all(4.r),
                                  decoration: const BoxDecoration(
                                    color: AppColors.danger,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Text(
                                    '${controller.notificationCount.value}',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 9.sp,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              )
                            : const SizedBox.shrink(),
                      ),
                    ],
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
                          ),
                        ),
                        SizedBox(height: 12.h),
                        AppPrimaryButton(
                          label: AppStrings.searchNeighborhood,
                          icon: const Icon(
                            Icons.search_rounded,
                            size: 18,
                            color: Colors.white,
                          ),
                          height: 48,
                          onPressed: () => controller.searchNeighborhood(),
                        ),
                        SizedBox(height: 10.h),
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
                      households: controller.nearbyHouseholds,
                      onTap: () {
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
                            'Updated 2 days ago',
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
                      () => Column(
                        children: [
                          ListView.separated(
                            padding: EdgeInsets.zero,
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: controller.nearbyHouseholds.length > 5
                                ? 5
                                : controller.nearbyHouseholds.length,
                            separatorBuilder: (context, _) => const Divider(
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
                                    onUpdated: (updated) =>
                                        controller.updateHousehold(updated),
                                  );
                                },
                              );
                            },
                          ),
                          const Divider(color: AppColors.border, height: 1),
                          InkWell(
                            onTap: () {
                              if (Get.isRegistered<MainNavController>()) {
                                Get.find<MainNavController>().changeDestination(
                                  MainNavDestination.neighborhood,
                                );
                              }
                            },
                            child: Container(
                              padding: EdgeInsets.symmetric(vertical: 14.h),
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
}
