import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:gps_cielo/core/constants/app_colors.dart';
import 'package:gps_cielo/core/constants/app_typography.dart';
import 'package:gps_cielo/core/utils/search_range.dart';
import 'package:gps_cielo/features/prayer_list/domain/services/prayer_list_service.dart';
import 'package:gps_cielo/shared/widgets/buttons/app_primary_button.dart';
import 'package:gps_cielo/features/prayer_list/presentation/controllers/prayer_list_controller.dart';
import 'package:gps_cielo/features/prayer_list/presentation/widgets/prayer_list_item_card.dart';
import 'package:gps_cielo/features/prayer_list/presentation/widgets/prayer_progress_card.dart';
import 'package:gps_cielo/features/main_nav/presentation/controllers/main_nav_controller.dart';
import 'package:gps_cielo/features/main_nav/presentation/models/main_nav_destination.dart';
import 'package:gps_cielo/shared/widgets/layout/collapsing_header_scroll_view.dart';

class PrayerListScreen extends GetView<PrayerListController> {
  const PrayerListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: CollapsingHeaderScrollView(
        title: 'Prayer List',
        onRefresh: controller.loadTodayPrayers,
        subtitle: Obx(() {
          final plan = controller.plan.value;
          return Text(
            plan.cycleTotal == 0
                ? 'Your daily prayers for the neighbors nearest your home'
                : 'Today \u2022 ${plan.today.length} of your '
                      '${plan.cycleTotal} neighbors',
          );
        }),
        // Today's progress stays in view while scrolling the list.
        pinnedHeight: 46.h,
        pinned: Obx(() => _TodayStrip(plan: controller.plan.value)),
        slivers: [
          SliverPadding(
            padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 0),
            sliver: SliverToBoxAdapter(
              child: Obx(() => PrayerProgressCard(plan: controller.plan.value)),
            ),
          ),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(16.w, 14.h, 16.w, 0),
            sliver: Obx(() => _buildBody()),
          ),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 0),
            sliver: SliverToBoxAdapter(
              child: Column(
                children: [
                  _buildVerse(),
                  SizedBox(height: 12.h),
                  _buildReminder(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Today's households, or why there are none.
  Widget _buildBody() {
    final plan = controller.plan.value;
    if (controller.isLoading.value && plan.cycleTotal == 0) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 32.h),
          child: const Center(child: CircularProgressIndicator()),
        ),
      );
    }
    if (!controller.hasHome.value) {
      return SliverToBoxAdapter(
        child: AppNoticeCard(
          icon: Icons.home_outlined,
          title: 'Set your home address',
          message:
              'Your daily prayer list is built from the households '
              'nearest your home.',
          actions: [_settingsButton('Add my address', Icons.home_outlined)],
        ),
      );
    }
    if (plan.cycleTotal == 0) {
      final meters = controller.rangeMeters.value;
      final range = meters == null
          ? 'your range'
          : SearchRange.formatDistance(meters);
      return SliverToBoxAdapter(
        child: AppNoticeCard(
          icon: Icons.travel_explore_rounded,
          title: 'No households near your home yet',
          message:
              'None within $range of ${controller.homeLabel.value}. '
              'Choose a larger search range or change your home address.',
          actions: [
            _settingsButton('Search range', Icons.tune_rounded),
            _settingsButton('Home address', Icons.home_outlined),
          ],
        ),
      );
    }

    final notices = <Widget>[
      if (plan.isCycleComplete) _buildCycleComplete(plan),
      if (!plan.isCycleComplete && plan.isTodayDone)
        AppNoticeCard(
          icon: Icons.check_circle_rounded,
          title: "Today's prayers are done",
          message:
              'Thank you! Tomorrow brings the next '
              '${plan.dailyTarget} neighbors.',
        ),
    ];

    return SliverMainAxisGroup(
      slivers: [
        for (final notice in notices)
          SliverPadding(
            padding: EdgeInsets.only(bottom: 12.h),
            sliver: SliverToBoxAdapter(child: notice),
          ),
        SliverList.separated(
          itemCount: plan.today.length,
          separatorBuilder: (context, _) => SizedBox(height: 12.h),
          itemBuilder: (context, index) {
            final household = plan.today[index];
            return PrayerListItemCard(
              key: ValueKey('prayer-item-${household.id}'),
              household: household,
              onPrayToggle: () => controller.togglePray(household),
              onUpdated: controller.updateHousehold,
            );
          },
        ),
      ],
    );
  }

  /// Opens Profile, where the address and Prayer preferences are set.
  Widget _settingsButton(String label, IconData icon) {
    return OutlinedButton.icon(
      onPressed: () {
        if (Get.isRegistered<MainNavController>()) {
          Get.find<MainNavController>().changeDestination(
            MainNavDestination.profile,
          );
        }
      },
      icon: Icon(icon, size: 16.r),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.primaryNavy,
        side: const BorderSide(color: AppColors.border),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10.r),
        ),
        textStyle: AppTypography.label(
          fontSize: 12.5.sp,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildVerse() {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(14.r),
      decoration: BoxDecoration(
        color: const Color(0xFF26375A),
        borderRadius: BorderRadius.circular(16.r),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '"So then, as we have opportunity, let us do good to everyone, '
            'and especially to those who are of the household of faith."',
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
    );
  }

  Widget _buildReminder() {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(16.r),
      decoration: BoxDecoration(
        color: const Color(0xFF1B2A4A),
        borderRadius: BorderRadius.circular(16.r),
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
    );
  }

  Widget _buildCycleComplete(PrayerPlan plan) {
    return AppNoticeCard(
      icon: Icons.celebration_rounded,
      highlight: true,
      title: 'Prayer cycle complete',
      message:
          'You have prayed for all ${plan.cycleTotal} households in '
          'your neighborhood. Start a new cycle to pray for them again.',
      actions: [
        Obx(
          () => SizedBox(
            width: 180.w,
            child: AppPrimaryButton(
              key: const ValueKey('start-new-cycle'),
              label: 'Start new cycle',
              height: 42,
              isLoading: controller.isStartingCycle.value,
              onPressed: controller.startNewCycle,
            ),
          ),
        ),
      ],
    );
  }
}

/// Sticky strip: today's progress toward the daily goal.
class _TodayStrip extends StatelessWidget {
  const _TodayStrip({required this.plan});

  final PrayerPlan plan;

  @override
  Widget build(BuildContext context) {
    final total = plan.today.length;
    final done = plan.today.where((h) => h.isPrayed).length;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16.w),
      child: Row(
        children: [
          Icon(
            Icons.favorite_rounded,
            size: 16.r,
            color: AppColors.primaryGold,
          ),
          SizedBox(width: 8.w),
          Text(
            total == 0 ? 'Nothing to pray for yet' : '$done of $total today',
            key: const ValueKey('today-strip'),
            style: AppTypography.label(
              color: AppColors.textPrimary,
              fontSize: 13.sp,
              fontWeight: FontWeight.w700,
            ),
          ),
          SizedBox(width: 12.w),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4.r),
              child: LinearProgressIndicator(
                value: total == 0 ? 0 : done / total,
                minHeight: 6.h,
                backgroundColor: const Color(0xFFE2E8F0),
                valueColor: const AlwaysStoppedAnimation(Color(0xFF2E7D32)),
              ),
            ),
          ),
          if (plan.dailyTarget > 0) ...[
            SizedBox(width: 12.w),
            Text(
              'Goal ${plan.dailyTarget}/day',
              style: AppTypography.body(
                color: AppColors.textSecondary,
                fontSize: 11.5.sp,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
