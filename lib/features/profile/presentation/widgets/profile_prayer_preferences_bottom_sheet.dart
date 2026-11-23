import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:gps_cielo/core/constants/app_colors.dart';
import 'package:gps_cielo/core/constants/app_typography.dart';
import 'package:gps_cielo/core/utils/search_range.dart';
import 'package:gps_cielo/shared/widgets/buttons/app_primary_button.dart';
import 'package:gps_cielo/shared/widgets/inputs/option_chips.dart';

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
              child: Obx(() {
                final goal = selectedTargetRx.value;
                final homes = selectedRadiusRx.value;
                final km = selectedKmRx.value;
                final tooBig = {
                  for (final t in targets)
                    if (t > homes) t,
                };
                final note = roundLengthText(
                  homes,
                  goal,
                  lead: "At $goal a day you'll",
                );
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _sectionTitle('Daily goal'),
                    SizedBox(height: 4.h),
                    _sectionText(
                      'How many households would you like to pray for each day?',
                    ),
                    SizedBox(height: 12.h),
                    OptionChips(
                      options: targets,
                      selected: goal,
                      caption: 'a day',
                      keyPrefix: 'goal',
                      disabled: tooBig,
                      onSelected: (t) {
                        selectedTargetRx.value = t;
                        _goalLoweredRx.value = false;
                      },
                    ),
                    if (tooBig.isNotEmpty) ...[
                      SizedBox(height: 6.h),
                      Text(
                        'Goals more than your $homes homes are off.',
                        key: const ValueKey('goal-too-big-hint'),
                        style: AppTypography.body(
                          color: AppColors.textMuted,
                          fontSize: 11.sp,
                        ),
                      ),
                    ],

                    SizedBox(height: 22.h),

                    // Search range (distance). Not offered with cell
                    // households: the neighborhood is the nearest N homes.
                    if (SearchRange.userChoosesRange) ...[
                      _sectionTitle('Search range'),
                      SizedBox(height: 4.h),
                      _sectionText(
                        'Households are searched within this distance of your '
                        'home or a searched place.',
                      ),
                      SizedBox(height: 8.h),
                      Text(
                        'Within ${SearchRange.formatKm(km)}',
                        style: _valueStyle,
                      ),
                      SizedBox(height: 8.h),
                      Wrap(
                        spacing: 8.w,
                        runSpacing: 8.h,
                        children: [
                          for (final option in SearchRange.distanceOptionsKm)
                            ChoiceChip(
                              key: ValueKey('range-km-$option'),
                              label: Text(SearchRange.formatKm(option)),
                              selected: option == km,
                              showCheckmark: false,
                              selectedColor: AppColors.primaryNavy,
                              labelStyle: TextStyle(
                                color: option == km
                                    ? Colors.white
                                    : AppColors.textPrimary,
                                fontWeight: FontWeight.w600,
                              ),
                              onSelected: (_) => selectedKmRx.value = option,
                            ),
                        ],
                      ),
                      SizedBox(height: 22.h),
                    ],

                    _sectionTitle('Homes in my neighborhood'),
                    SizedBox(height: 4.h),
                    _sectionText(
                      SearchRange.userChoosesRange
                          ? 'Your neighborhood is this many homes nearest your '
                                'home, within the search range. Home, '
                                'Neighborhood and your prayer rounds all use it.'
                          : 'Your neighborhood is this many homes nearest your '
                                'home. Home, Neighborhood and your prayer '
                                'rounds all use it.',
                    ),
                    SizedBox(height: 8.h),
                    Text('Nearest $homes homes', style: _valueStyle),
                    SizedBox(height: 8.h),
                    OptionChips(
                      options: SearchRange.options,
                      selected: homes,
                      keyPrefix: 'homes',
                      onSelected: (h) {
                        selectedRadiusRx.value = h;
                        // Keep the daily goal within the neighborhood.
                        final lowered = SearchRange.clampGoal(
                          selectedTargetRx.value,
                          h,
                        );
                        if (lowered != selectedTargetRx.value) {
                          selectedTargetRx.value = lowered;
                          _goalLoweredRx.value = true;
                        }
                      },
                    ),

                    // Says why the daily goal just changed.
                    if (_goalLoweredRx.value)
                      Container(
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
                      ),

                    if (note != null) ...[
                      SizedBox(height: 16.h),
                      GoalNote(key: const ValueKey('round-note'), text: note),
                    ],

                    SizedBox(height: 20.h),

                    AppPrimaryButton(
                      label: 'Save Preferences',
                      onPressed: () {
                        widget.onSavePreferences(goal, homes, km);
                        _close();
                      },
                    ),
                  ],
                );
              }),
            ),
          ),
        ],
      ),
    );
  }

  TextStyle get _valueStyle => AppTypography.heading(
    color: AppColors.primaryNavy,
    fontSize: 14.sp,
    fontWeight: FontWeight.w800,
  );

  Widget _sectionTitle(String text) => Text(
    text,
    style: AppTypography.heading(
      color: AppColors.textPrimary,
      fontSize: 14.sp,
      fontWeight: FontWeight.w700,
    ),
  );

  Widget _sectionText(String text) => Text(
    text,
    style: TextStyle(
      color: const Color(0xFF64748B),
      fontSize: 13.sp,
      height: 1.35,
    ),
  );

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
