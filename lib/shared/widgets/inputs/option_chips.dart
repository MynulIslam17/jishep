import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:gps_cielo/core/constants/app_colors.dart';
import 'package:gps_cielo/core/constants/app_typography.dart';

/// A row of equal-width number chips (Figma "3 · 5 · 10 · 15"); the selected
/// one is navy. [caption] adds a small line under each number ("a day").
class OptionChips extends StatelessWidget {
  const OptionChips({
    required this.options,
    required this.selected,
    required this.onSelected,
    this.caption,
    this.keyPrefix = 'option',
    this.disabled = const {},
    super.key,
  });

  final List<int> options;
  final int selected;
  final ValueChanged<int> onSelected;
  final String? caption;

  /// Keys are '$keyPrefix-$option' (for tests).
  final String keyPrefix;

  /// Options that can't be picked (shown faded).
  final Set<int> disabled;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < options.length; i++) ...[
          if (i > 0) SizedBox(width: 8.w),
          Expanded(child: _chip(options[i])),
        ],
      ],
    );
  }

  Widget _chip(int option) {
    final isSelected = option == selected;
    final isDisabled = disabled.contains(option);
    return Semantics(
      selected: isSelected,
      button: true,
      child: GestureDetector(
        key: ValueKey('$keyPrefix-$option'),
        behavior: HitTestBehavior.opaque,
        onTap: isDisabled ? null : () => onSelected(option),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          height: (caption == null ? 40 : 52).h,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isSelected ? AppColors.primaryNavy : AppColors.surface,
            borderRadius: BorderRadius.circular(10.r),
            border: Border.all(
              color: isSelected ? AppColors.primaryNavy : AppColors.border,
            ),
          ),
          child: Opacity(
            opacity: isDisabled ? 0.4 : 1,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$option',
                  style: AppTypography.heading(
                    color: isSelected ? Colors.white : AppColors.textPrimary,
                    fontSize: (caption == null ? 14 : 17).sp,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (caption != null)
                  Text(
                    caption!,
                    style: AppTypography.body(
                      color: isSelected
                          ? Colors.white.withValues(alpha: 0.8)
                          : AppColors.textSecondary,
                      fontSize: 9.5.sp,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Yellow note with a clock icon ("You'll pray for all 50 neighbors in
/// about 10 days").
class GoalNote extends StatelessWidget {
  const GoalNote({required this.text, super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF3C7),
        borderRadius: BorderRadius.circular(10.r),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.schedule_rounded,
            size: 16.r,
            color: const Color(0xFFB45309),
          ),
          SizedBox(width: 8.w),
          Expanded(
            child: Text(
              text,
              style: AppTypography.body(
                color: const Color(0xFF92400E),
                fontSize: 12.sp,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// "You'll pray for all 50 neighbors in about 10 days." (null when unknown).
String? roundLengthText(int homes, int perDay, {String lead = "You'll"}) {
  if (homes <= 0 || perDay <= 0) return null;
  final days = (homes / perDay).ceil();
  return '$lead pray for all $homes ${homes == 1 ? 'neighbor' : 'neighbors'} '
      'in about $days ${days == 1 ? 'day' : 'days'}. Then a new round starts.';
}
