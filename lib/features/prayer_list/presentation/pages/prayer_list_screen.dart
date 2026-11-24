import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:gps_cielo/features/profile/presentation/widgets/primary_location_help.dart';
import 'package:gps_cielo/core/constants/app_strings.dart';
import 'package:gps_cielo/core/constants/app_colors.dart';
import 'package:gps_cielo/core/constants/app_typography.dart';
import 'package:gps_cielo/core/utils/search_range.dart';
import 'package:gps_cielo/features/prayer_list/presentation/controllers/prayer_list_controller.dart';
import 'package:gps_cielo/core/models/household_model.dart';
import 'package:gps_cielo/shared/widgets/bottom_sheets/household_detail_bottom_sheet.dart';
import 'package:gps_cielo/shared/widgets/household/household_row.dart';
import 'package:gps_cielo/shared/widgets/household/today_neighbors_card.dart';
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
          final n = plan.today.length;
          return Text(
            plan.cycleTotal == 0
                ? 'Your daily prayers for the neighbors nearest your home'
                : plan.isCycleComplete
                ? 'Round complete \u2022 ${plan.cycleTotal} neighbors'
                : 'Today \u2022 $n ${n == 1 ? 'neighbor' : 'neighbors'}',
            key: const ValueKey('prayer-list-subtitle'),
          );
        }),
        slivers: [
          SliverPadding(
            padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 0),
            sliver: SliverToBoxAdapter(child: _buildVerse()),
          ),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 24.h),
            sliver: Obx(() => _buildBody()),
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
    if (plan.cycleTotal == 0 && controller.homeUnavailable.value) {
      return SliverToBoxAdapter(
        child: AppNoticeCard(
          icon: Icons.travel_explore_rounded,
          title: AppStrings.areaUnavailable,
          message:
              controller.homeNote.value ??
              'Household data for the area around '
                  '${controller.homeLabel.value} has not been added yet. '
                  '${AppStrings.areaComingSoon}',
          actions: [PrimaryLocationHelp.button()],
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
          message: SearchRange.userChoosesRange
              ? 'None within $range of ${controller.homeLabel.value}. '
                    'Choose a larger search range or change your home '
                    'address.'
              : 'None found near ${controller.homeLabel.value}. '
                    'Try changing your home address.',
          actions: [
            if (SearchRange.userChoosesRange)
              _settingsButton('Search range', Icons.tune_rounded),
            _settingsButton('Home address', Icons.home_outlined),
          ],
        ),
      );
    }

    if (plan.isCycleComplete) {
      return SliverToBoxAdapter(
        child: RoundCompleteCard(
          plan: plan,
          visited: controller.visitedCount,
          invited: controller.invitedCount,
          isStarting: controller.isStartingCycle.value,
          onStartNewRound: controller.startNewCycle,
        ),
      );
    }

    final next = plan.isTodayDone
        ? controller.nextNeighbors
        : const <HouseholdModel>[];
    final showNext = controller.showNext.value && next.isNotEmpty;

    return SliverMainAxisGroup(
      slivers: [
        SliverToBoxAdapter(child: TodayNeighborsCard(plan: plan)),
        if (plan.isTodayDone)
          SliverPadding(
            padding: EdgeInsets.only(top: 12.h),
            sliver: SliverToBoxAdapter(
              child: GoalReachedCard(
                plan: plan,
                showingNext: showNext,
                onNextNeighbors: next.isEmpty ? null : controller.toggleNext,
              ),
            ),
          ),
        SliverPadding(
          padding: EdgeInsets.only(top: 20.h, bottom: 10.h),
          sliver: SliverToBoxAdapter(
            child: _sectionHeader(
              'Today',
              '${plan.countedToday} of ${plan.todayGoal} prayed',
              key: const ValueKey('today-header'),
            ),
          ),
        ),
        _rows(plan.today, 'prayer-item'),
        if (showNext) ...[
          SliverPadding(
            padding: EdgeInsets.only(top: 20.h, bottom: 10.h),
            sliver: SliverToBoxAdapter(
              child: _sectionHeader(
                'Next neighbors',
                'Extra prayers today',
                key: const ValueKey('next-header'),
              ),
            ),
          ),
          _rows(next, 'next-item'),
        ],
      ],
    );
  }

  Widget _rows(List<HouseholdModel> homes, String keyPrefix) {
    return SliverList.separated(
      itemCount: homes.length,
      separatorBuilder: (context, _) => SizedBox(height: 10.h),
      itemBuilder: (context, index) {
        final household = homes[index];
        void pray() => controller.togglePray(household);
        return KeyedSubtree(
          key: ValueKey('$keyPrefix-${household.id}'),
          child: HouseholdRow(
            household: household,
            onPrayToggle: pray,
            onTap: () => HouseholdDetailBottomSheet.show(
              context,
              household: household,
              onPrayToggle: pray,
              onUpdated: controller.updateHousehold,
            ),
          ),
        );
      },
    );
  }

  Widget _sectionHeader(String title, String trailing, {Key? key}) {
    return Row(
      key: key,
      children: [
        Expanded(
          child: Text(
            title,
            style: AppTypography.heading(
              color: AppColors.textPrimary,
              fontSize: 16.sp,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        Text(
          trailing,
          style: AppTypography.body(
            color: AppColors.textSecondary,
            fontSize: 12.sp,
          ),
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
      key: const ValueKey('verse-card'),
      width: double.infinity,
      padding: EdgeInsets.all(14.r),
      decoration: BoxDecoration(
        color: AppColors.primaryNavy,
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
}
