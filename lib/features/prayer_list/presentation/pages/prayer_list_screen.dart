import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:gps_cielo/core/constants/app_colors.dart';
import 'package:gps_cielo/core/constants/app_typography.dart';
import 'package:gps_cielo/core/utils/app_system_insets.dart';
import 'package:gps_cielo/features/prayer_list/presentation/controllers/prayer_list_controller.dart';
import 'package:gps_cielo/features/prayer_list/presentation/widgets/prayer_list_item_card.dart';
import 'package:gps_cielo/features/prayer_list/presentation/widgets/prayer_progress_card.dart';

class PrayerListScreen extends GetView<PrayerListController> {
  const PrayerListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final topInset = AppSystemInsets.top(context);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Column(
          children: [
            // Navy Header
            Container(
              width: double.infinity,
              padding: EdgeInsets.fromLTRB(20.w, topInset + 10.h, 20.w, 18.h),
              color: AppColors.primaryNavy,
              child: Column(
                children: [
                  // Title Row with Live Household Count
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Prayer List',
                          style: AppTypography.heading(
                            color: AppColors.textWhite,
                            fontSize: 20.sp,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        SizedBox(height: 2.h),
                        Obx(
                          () => Text(
                            'Today \u2022 ${controller.todayHouseholds.length} households',
                            style: AppTypography.body(
                              color: AppColors.textWhite.withValues(alpha: 0.75),
                              fontSize: 12.sp,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  SizedBox(height: 14.h),

                  // Scripture Banner
                  Container(
                    width: double.infinity,
                    padding: EdgeInsets.all(14.r),
                    decoration: BoxDecoration(
                      color: const Color(0xFF26375A),
                      borderRadius: BorderRadius.circular(14.r),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '"So then, as we have opportunity, let us do good to everyone, and especially to those who are of the household of faith."',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12.5.sp,
                            fontStyle: FontStyle.italic,
                            height: 1.4,
                          ),
                        ),
                        SizedBox(height: 8.h),
                        Text(
                          '\u2014 Galatians 6:10',
                          style: AppTypography.label(
                            color: AppColors.primaryGold,
                            fontSize: 11.5.sp,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Content Area
            Padding(
              padding: EdgeInsets.all(16.r),
              child: Column(
                children: [
                  // Today's Progress Card
                  Obx(
                    () => PrayerProgressCard(
                      cycleCompleted: controller.cycleCompleted.value,
                      cycleTarget: controller.cycleTarget.value,
                      prayedTodayCount: controller.prayedTodayCount,
                      todayHouseholds: controller.todayHouseholds,
                    ),
                  ),

                  SizedBox(height: 14.h),

                  // Reactive Household List with Status Display Badges
                  Obx(() {
                    if (controller.isLoading.value) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    return ListView.separated(
                      padding: EdgeInsets.zero,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: controller.todayHouseholds.length,
                      separatorBuilder: (context, _) => SizedBox(height: 12.h),
                      itemBuilder: (context, index) {
                        final household = controller.todayHouseholds[index];
                        return PrayerListItemCard(
                          household: household,
                          onPrayToggle: () => controller.togglePray(household),
                          onUpdated: (updated) => controller.updateHousehold(updated),
                        );
                      },
                    );
                  }),

                  SizedBox(height: 16.h),

                  // Bottom Scripture Reminder Card
                  Container(
                    width: double.infinity,
                    padding: EdgeInsets.all(16.r),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1B2A4A),
                      borderRadius: BorderRadius.circular(14.r),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'REMEMBER',
                          style: AppTypography.label(
                            color: AppColors.primaryGold,
                            fontSize: 11.sp,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.8,
                          ),
                        ),
                        SizedBox(height: 8.h),
                        Text(
                          '"Go into all the world and preach the gospel to every creature."',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 13.sp,
                            fontStyle: FontStyle.italic,
                            height: 1.4,
                          ),
                        ),
                        SizedBox(height: 8.h),
                        Text(
                          '\u2014 Mark 16:15',
                          style: AppTypography.label(
                            color: AppColors.primaryGold,
                            fontSize: 12.sp,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),

                  SizedBox(height: 24.h),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
