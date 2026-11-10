import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:gps_cielo/core/constants/app_assets.dart';
import 'package:gps_cielo/core/constants/app_colors.dart';
import 'package:gps_cielo/core/constants/app_typography.dart';
import 'package:gps_cielo/core/utils/system_ui_config.dart';
import 'package:gps_cielo/features/donation/domain/services/donation_service.dart';
import 'package:gps_cielo/features/donation/presentation/controllers/donation_controller.dart';
import 'package:gps_cielo/shared/widgets/buttons/app_back_button.dart';
import 'package:gps_cielo/shared/widgets/inputs/app_segmented_switch.dart';
import 'package:gps_cielo/shared/widgets/layout/collapsing_header_scroll_view.dart';

/// "Support the mission" — pick one-time / monthly and an amount, then
/// continue to Stripe's secure page in the browser.
///
/// Uses the same collapsing large-title header as the main tabs.
class DonationScreen extends GetView<DonationController> {
  const DonationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiConfig.darkOverlay,
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(),
          behavior: HitTestBehavior.translucent,
          child: CollapsingHeaderScrollView(
            title: 'Support the mission',
            subtitle: const Text('Give once or monthly to GPS PARA EL CIELO'),
            leading: const AppBackButton(size: 36),
            slivers: [
              SliverPadding(
                padding: EdgeInsets.all(16.r),
                sliver: SliverList.list(
                  children: [
                    const _MissionCard(),
                    SizedBox(height: 16.h),
                    const _AmountCard(),
                    SizedBox(height: 16.h),
                    const _ImpactCard(),
                  ],
                ),
              ),
            ],
          ),
        ),
        bottomNavigationBar: const _DonateBar(),
      ),
    );
  }
}

// --- Mission ---

class _MissionCard extends StatelessWidget {
  const _MissionCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(16.r),
      decoration: BoxDecoration(
        gradient: AppColors.navyGradient,
        borderRadius: BorderRadius.circular(20.r),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 64.r,
                height: 64.r,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16.r),
                  border: Border.all(
                    color: AppColors.primaryGold.withValues(alpha: 0.6),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primaryGold.withValues(alpha: 0.25),
                      blurRadius: 20,
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14.r),
                  child: Transform.scale(
                    scale: 1.06,
                    child: Image.asset(
                      AppAssets.appLogoRound,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              ),
              SizedBox(width: 14.w),
              Expanded(
                child: Text(
                  'Your gift keeps the app free and helps believers pray '
                  'for every home in their neighborhood.',
                  style: AppTypography.body(
                    color: AppColors.textWhite.withValues(alpha: 0.88),
                    fontSize: 13.sp,
                    height: 1.45,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 14.h),
          Divider(height: 1, color: Colors.white.withValues(alpha: 0.12)),
          SizedBox(height: 12.h),
          Text(
            '“Each of you should give what you have decided in your heart '
            'to give.”  — 2 Corinthians 9:7',
            style: AppTypography.body(
              color: AppColors.primaryGoldLight,
              fontSize: 11.5.sp,
              fontStyle: FontStyle.italic,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

// --- Amount picker ---

class _AmountCard extends GetView<DonationController> {
  const _AmountCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(16.r),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20.r),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Obx(
            () => AppSegmentedSwitch(
              labels: const ['One-time', 'Monthly'],
              icons: const [
                Icons.favorite_border_rounded,
                Icons.autorenew_rounded,
              ],
              selectedIndex: controller.frequency.value.index,
              onChanged: controller.setFrequency,
            ),
          ),
          SizedBox(height: 18.h),
          _sectionLabel('CHOOSE AN AMOUNT'),
          SizedBox(height: 10.h),
          Obx(() {
            final selected = controller.selectedPreset.value;
            return GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: EdgeInsets.zero,
              mainAxisSpacing: 10.h,
              crossAxisSpacing: 10.w,
              childAspectRatio: 1.9,
              children: [
                for (final value in controller.presets)
                  _AmountChip(
                    amount: value,
                    selected: selected == value,
                    onTap: () => controller.selectPreset(value),
                  ),
              ],
            );
          }),
          SizedBox(height: 16.h),
          _sectionLabel('OR ENTER YOUR OWN'),
          SizedBox(height: 10.h),
          Obx(() {
            final active = controller.customAmount.value != null;
            return TextField(
              controller: controller.customController,
              focusNode: controller.customFocus,
              onChanged: controller.onCustomChanged,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(5),
              ],
              style: AppTypography.heading(
                color: AppColors.textPrimary,
                fontSize: 18.sp,
                fontWeight: FontWeight.w700,
              ),
              decoration: InputDecoration(
                hintText: 'Other amount',
                hintStyle: AppTypography.body(
                  color: AppColors.textMuted,
                  fontSize: 15.sp,
                ),
                prefixIcon: Padding(
                  padding: EdgeInsets.only(left: 16.w, right: 6.w),
                  child: Text(
                    '\$',
                    style: AppTypography.heading(
                      color: active
                          ? AppColors.primaryGoldDark
                          : AppColors.textMuted,
                      fontSize: 18.sp,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                prefixIconConstraints: const BoxConstraints(),
                suffixText: 'USD',
                suffixStyle: AppTypography.label(
                  color: AppColors.textMuted,
                  fontSize: 12.sp,
                ),
                filled: true,
                fillColor: active
                    ? AppColors.primaryGold.withValues(alpha: 0.08)
                    : AppColors.inputSurface,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 16.w,
                  vertical: 14.h,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12.r),
                  borderSide: const BorderSide(color: AppColors.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12.r),
                  borderSide: BorderSide(
                    color: active ? AppColors.primaryGold : AppColors.border,
                    width: active ? 1.6 : 1,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12.r),
                  borderSide: const BorderSide(
                    color: AppColors.primaryGold,
                    width: 1.6,
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}

Widget _sectionLabel(String text) => Text(
  text,
  style: AppTypography.label(
    color: AppColors.textSecondary,
    fontSize: 11.sp,
    fontWeight: FontWeight.w700,
    letterSpacing: 1.2,
  ),
);

class _AmountChip extends StatelessWidget {
  const _AmountChip({
    required this.amount,
    required this.selected,
    required this.onTap,
  });

  final int amount;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? AppColors.primaryNavy : AppColors.surface,
          borderRadius: BorderRadius.circular(12.r),
          border: Border.all(
            color: selected ? AppColors.primaryGold : AppColors.border,
            width: selected ? 2 : 1,
          ),
        ),
        child: Text(
          '\$$amount',
          style: AppTypography.heading(
            color: selected ? AppColors.textWhite : AppColors.textPrimary,
            fontSize: 17.sp,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

// --- Where it goes ---

class _ImpactCard extends StatelessWidget {
  const _ImpactCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(16.r),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20.r),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionLabel('WHERE YOUR GIFT GOES'),
          SizedBox(height: 12.h),
          const _ImpactRow(
            icon: Icons.phone_iphone_rounded,
            title: 'Keep the app free',
            subtitle: 'Servers, maps and updates for every prayer walker.',
          ),
          const _ImpactRow(
            icon: Icons.travel_explore_rounded,
            title: 'Reach new neighborhoods',
            subtitle: 'Bring GPS PARA EL CIELO to more cities and churches.',
          ),
          const _ImpactRow(
            icon: Icons.volunteer_activism_rounded,
            title: 'Equip local outreach',
            subtitle: 'Resources for follow-up visits and prayer teams.',
            last: true,
          ),
        ],
      ),
    );
  }
}

class _ImpactRow extends StatelessWidget {
  const _ImpactRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.last = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool last;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: last ? 0 : 14.h),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38.r,
            height: 38.r,
            decoration: BoxDecoration(
              color: AppColors.primaryGold.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(10.r),
            ),
            child: Icon(icon, size: 20.r, color: AppColors.primaryGoldDark),
          ),
          SizedBox(width: 12.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTypography.heading(
                    color: AppColors.textPrimary,
                    fontSize: 14.sp,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(height: 2.h),
                Text(
                  subtitle,
                  style: AppTypography.body(
                    color: AppColors.textSecondary,
                    fontSize: 12.sp,
                    height: 1.35,
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

// --- Sticky donate bar ---

class _DonateBar extends GetView<DonationController> {
  const _DonateBar();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        16.w,
        12.h,
        16.w,
        12.h + MediaQuery.paddingOf(context).bottom,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: const Border(top: BorderSide(color: AppColors.border)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Obx(() {
            final amount = controller.amount;
            final monthly =
                controller.frequency.value == DonationFrequency.monthly;
            final valid = controller.isAmountValid;
            final loading = controller.isLoading.value;
            final label = valid
                ? 'Give \$$amount${monthly ? ' / month' : ''}'
                : 'Choose an amount';

            return SizedBox(
              width: double.infinity,
              height: 54.h,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: valid ? AppColors.goldGradient : null,
                  color: valid ? null : AppColors.border,
                  borderRadius: BorderRadius.circular(14.r),
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14.r),
                    onTap: loading ? null : controller.donate,
                    child: Center(
                      child: loading
                          ? SizedBox.square(
                              dimension: 22.r,
                              child: const CircularProgressIndicator(
                                color: AppColors.primaryNavy,
                                strokeWidth: 2.4,
                              ),
                            )
                          : Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.favorite_rounded,
                                  size: 18.r,
                                  color: valid
                                      ? AppColors.primaryNavy
                                      : AppColors.textMuted,
                                ),
                                SizedBox(width: 8.w),
                                Text(
                                  label,
                                  style: AppTypography.heading(
                                    color: valid
                                        ? AppColors.primaryNavy
                                        : AppColors.textMuted,
                                    fontSize: 16.sp,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
                ),
              ),
            );
          }),
          SizedBox(height: 10.h),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.lock_rounded, size: 13.r, color: AppColors.textMuted),
              SizedBox(width: 5.w),
              Flexible(
                child: Text(
                  'Secure payment by Stripe · opens in your browser',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.body(
                    color: AppColors.textMuted,
                    fontSize: 11.5.sp,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
