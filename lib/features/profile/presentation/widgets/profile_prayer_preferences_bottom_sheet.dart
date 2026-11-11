import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:gps_cielo/core/constants/app_colors.dart';
import 'package:gps_cielo/core/constants/app_typography.dart';
import 'package:gps_cielo/core/utils/search_range.dart';
import 'package:gps_cielo/shared/widgets/buttons/app_primary_button.dart';

class ProfilePrayerPreferencesBottomSheet extends StatefulWidget {
  final int initialTarget;
  final int initialRadius;

  final double initialRangeKm;

  /// Called with (daily target, default number of households, range in km).
  final void Function(int target, int radiusHomes, double rangeKm)
  onSavePreferences;

  /// From the [DraggableScrollableSheet] in [show], so dragging the content
  /// down (when scrolled to the top) pulls the sheet down and closes it.
  final ScrollController? scrollController;

  const ProfilePrayerPreferencesBottomSheet({
    required this.initialTarget,
    required this.onSavePreferences,
    this.initialRadius = SearchRange.defaultHomes,
    this.initialRangeKm = SearchRange.defaultKm,
    this.scrollController,
    super.key,
  });

  static void show(
    BuildContext context, {
    required int initialTarget,
    required void Function(int target, int radiusHomes, double rangeKm)
    onSavePreferences,
    double initialRangeKm = SearchRange.defaultKm,
    int initialRadius = SearchRange.defaultHomes,
  }) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      // Keeps the sheet (and its close button) below the status bar / notch.
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.9,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        snap: true,
        builder: (ctx, scrollController) => ProfilePrayerPreferencesBottomSheet(
          initialTarget: initialTarget,
          initialRadius: initialRadius,
          initialRangeKm: initialRangeKm,
          onSavePreferences: onSavePreferences,
          scrollController: scrollController,
        ),
      ),
    );
  }

  @override
  State<ProfilePrayerPreferencesBottomSheet> createState() =>
      _ProfilePrayerPreferencesBottomSheetState();
}

class _ProfilePrayerPreferencesBottomSheetState
    extends State<ProfilePrayerPreferencesBottomSheet> {
  static const _targets = SearchRange.goalOptions;

  // Kept in State so a rebuild never resets what the user picked.
  late final _selectedRadiusRx = SearchRange.normalize(
    widget.initialRadius,
  ).obs;

  /// A goal saved before the limit existed (e.g. 15 a day among 10 homes)
  /// opens already lowered, with the note saying why.
  late final _selectedTargetRx = SearchRange.clampGoal(
    widget.initialTarget,
    _selectedRadiusRx.value,
  ).obs;

  /// True after the goal was lowered to fit a smaller neighborhood.
  late final _goalLoweredRx =
      (_selectedTargetRx.value != widget.initialTarget).obs;
  late final _selectedKmRx = SearchRange.normalizeKm(widget.initialRangeKm).obs;

  void _close() => Navigator.of(context).maybePop();

  @override
  Widget build(BuildContext context) {
    final targets = _targets;
    final selectedTargetRx = _selectedTargetRx;
    final options = SearchRange.options;
    final selectedRadiusRx = _selectedRadiusRx;
    final selectedKmRx = _selectedKmRx;
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24.r)),
      ),
      child: Column(
        children: [
          // Fixed top: dragging it moves the sheet; X closes it.
          Padding(
            padding: EdgeInsets.fromLTRB(20.w, 12.h, 12.w, 0),
            child: Column(
              children: [
                _buildModalHandle(),
                SizedBox(height: 8.h),
                _buildModalHeader(title: 'Prayer Preferences'),
                SizedBox(height: 8.h),
              ],
            ),
          ),
          const Divider(color: AppColors.border, height: 1),
          Expanded(
            child: SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              controller: widget.scrollController,
              padding: EdgeInsets.fromLTRB(
                20.w,
                16.h,
                20.w,
                20.h + bottomInset,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'How many households would you like to pray for each day?',
                    style: TextStyle(
                      color: const Color(0xFF64748B),
                      fontSize: 13.sp,
                      height: 1.35,
                    ),
                  ),
                  SizedBox(height: 16.h),

                  Obx(
                    () => Column(
                      children: targets.map((target) {
                        final isSelected = selectedTargetRx.value == target;
                        // More than the neighborhood holds can never be met.
                        final fits = target <= selectedRadiusRx.value;
                        return GestureDetector(
                          key: ValueKey('goal-$target'),
                          onTap: fits
                              ? () {
                                  selectedTargetRx.value = target;
                                  _goalLoweredRx.value = false;
                                }
                              : null,
                          child: Container(
                            margin: EdgeInsets.only(bottom: 10.h),
                            padding: EdgeInsets.symmetric(
                              horizontal: 16.w,
                              vertical: 14.h,
                            ),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? const Color(0xFFF1F5F9)
                                  : Colors.white,
                              borderRadius: BorderRadius.circular(12.r),
                              border: Border.all(
                                color: isSelected
                                    ? AppColors.primaryNavy
                                    : const Color(0xFFE2E8F0),
                                width: isSelected ? 1.5 : 1.0,
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text.rich(
                                    TextSpan(
                                      text: '$target households / day',
                                      children: [
                                        if (!fits)
                                          TextSpan(
                                            text: '  more than your homes',
                                            style: TextStyle(
                                              fontSize: 11.sp,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                      ],
                                    ),
                                    style: TextStyle(
                                      color: fits
                                          ? AppColors.textPrimary
                                          : AppColors.textSecondary,
                                      fontSize: 14.sp,
                                      fontWeight: isSelected
                                          ? FontWeight.w700
                                          : FontWeight.w500,
                                    ),
                                  ),
                                ),
                                if (isSelected)
                                  Container(
                                    width: 22.r,
                                    height: 22.r,
                                    decoration: const BoxDecoration(
                                      color: AppColors.primaryNavy,
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      Icons.check_rounded,
                                      size: 14.r,
                                      color: Colors.white,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),

                  SizedBox(height: 10.h),
                  const Divider(color: AppColors.border, height: 1),
                  SizedBox(height: 16.h),

                  // Search range (distance)
                  _OptionSlider(
                    sliderKey: const ValueKey('range-km-slider'),
                    title: 'Search range',
                    description:
                        'Households are searched within this distance of your '
                        'home or a searched place.',
                    valueText: () =>
                        'Within ${SearchRange.formatKm(selectedKmRx.value)}',
                    labels: [
                      for (final km in SearchRange.distanceOptionsKm)
                        SearchRange.formatKm(km),
                    ],
                    index: () => SearchRange.distanceOptionsKm.indexOf(
                      selectedKmRx.value,
                    ),
                    onIndex: (i) =>
                        selectedKmRx.value = SearchRange.distanceOptionsKm[i],
                  ),

                  SizedBox(height: 10.h),
                  const Divider(color: AppColors.border, height: 1),
                  SizedBox(height: 16.h),

                  // Number of households (default for the Home filter)
                  _OptionSlider(
                    sliderKey: const ValueKey('default-radius-slider'),
                    title: 'Homes in my neighborhood',
                    description:
                        'Your neighborhood is this many homes nearest your '
                        'home, within the search range. Home, Neighborhood '
                        'and your prayer rounds all use it.',
                    valueText: () => 'Nearest ${selectedRadiusRx.value} homes',
                    labels: [for (final option in options) '$option'],
                    index: () => options.indexOf(selectedRadiusRx.value),
                    onIndex: (i) {
                      final homes = options[i];
                      selectedRadiusRx.value = homes;
                      // Keep the daily goal within the neighborhood.
                      final goal = SearchRange.clampGoal(
                        selectedTargetRx.value,
                        homes,
                      );
                      if (goal != selectedTargetRx.value) {
                        selectedTargetRx.value = goal;
                        _goalLoweredRx.value = true;
                      }
                    },
                  ),

                  // Says why the daily goal just changed.
                  Obx(() {
                    final goal = selectedTargetRx.value;
                    final homes = selectedRadiusRx.value;
                    if (!_goalLoweredRx.value) return const SizedBox.shrink();
                    return Container(
                      key: const ValueKey('goal-above-homes'),
                      margin: EdgeInsets.only(top: 12.h),
                      padding: EdgeInsets.all(12.r),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF3C7),
                        borderRadius: BorderRadius.circular(12.r),
                      ),
                      child: Text(
                        'Your daily goal is now $goal a day, so it fits the '
                        '$homes homes in your neighborhood.',
                        style: AppTypography.body(
                          color: const Color(0xFF92400E),
                          fontSize: 12.sp,
                          height: 1.35,
                        ),
                      ),
                    );
                  }),

                  SizedBox(height: 20.h),

                  AppPrimaryButton(
                    label: 'Save Preferences',
                    onPressed: () {
                      widget.onSavePreferences(
                        selectedTargetRx.value,
                        selectedRadiusRx.value,
                        selectedKmRx.value,
                      );
                      _close();
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModalHandle() {
    return Center(
      child: Container(
        width: 40.w,
        height: 4.h,
        decoration: BoxDecoration(
          color: const Color(0xFFCBD5E1),
          borderRadius: BorderRadius.circular(2.r),
        ),
      ),
    );
  }

  Widget _buildModalHeader({required String title}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(
          child: Text(
            title,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.heading(
              color: AppColors.primaryNavy,
              fontSize: 18.sp,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        // 44px tap target around the 32px circle.
        Semantics(
          button: true,
          label: 'Close',
          child: GestureDetector(
            key: const ValueKey('prefs-close'),
            behavior: HitTestBehavior.opaque,
            onTap: _close,
            child: Padding(
              padding: EdgeInsets.all(6.r),
              child: Container(
                width: 32.r,
                height: 32.r,
                decoration: const BoxDecoration(
                  color: Color(0xFFF1F5F9),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.close_rounded,
                  size: 18.r,
                  color: const Color(0xFF64748B),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// A titled slider over a fixed list of options.
class _OptionSlider extends StatelessWidget {
  const _OptionSlider({
    required this.sliderKey,
    required this.title,
    required this.description,
    required this.valueText,
    required this.labels,
    required this.index,
    required this.onIndex,
  });

  final Key sliderKey;
  final String title;
  final String description;
  final String Function() valueText;
  final List<String> labels;
  final int Function() index;
  final ValueChanged<int> onIndex;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: AppTypography.heading(
            color: AppColors.textPrimary,
            fontSize: 14.sp,
            fontWeight: FontWeight.w700,
          ),
        ),
        SizedBox(height: 4.h),
        Text(
          description,
          style: TextStyle(
            color: const Color(0xFF64748B),
            fontSize: 13.sp,
            height: 1.35,
          ),
        ),
        SizedBox(height: 8.h),
        Obx(() {
          final current = index().clamp(0, labels.length - 1);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                valueText(),
                style: AppTypography.heading(
                  color: AppColors.primaryNavy,
                  fontSize: 14.sp,
                  fontWeight: FontWeight.w800,
                ),
              ),
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 4.h,
                  activeTrackColor: AppColors.primaryNavy,
                  inactiveTrackColor: const Color(0xFFE2E8F0),
                  thumbColor: AppColors.primaryNavy,
                  overlayColor: AppColors.primaryNavy.withValues(alpha: 0.12),
                  activeTickMarkColor: Colors.white.withValues(alpha: 0.7),
                  inactiveTickMarkColor: AppColors.primaryNavy.withValues(
                    alpha: 0.25,
                  ),
                ),
                child: Slider(
                  key: sliderKey,
                  value: current.toDouble(),
                  max: (labels.length - 1).toDouble(),
                  divisions: labels.length - 1,
                  label: labels[current],
                  onChanged: (v) => onIndex(v.round()),
                ),
              ),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 14.r),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    for (var i = 0; i < labels.length; i++)
                      Text(
                        labels[i],
                        style: TextStyle(
                          color: i == current
                              ? AppColors.primaryNavy
                              : const Color(0xFF64748B),
                          fontSize: 10.5.sp,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          );
        }),
      ],
    );
  }
}
