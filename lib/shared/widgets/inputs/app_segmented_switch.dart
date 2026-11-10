import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:gps_cielo/core/constants/app_colors.dart';
import 'package:gps_cielo/core/constants/app_typography.dart';

/// Pill switch between a few options (e.g. Email / Phone).
///
/// One white thumb slides under the selected option, so a tap moves a
/// single indicator instead of flashing every segment. No ink ripple.
class AppSegmentedSwitch extends StatelessWidget {
  const AppSegmentedSwitch({
    super.key,
    required this.labels,
    required this.selectedIndex,
    required this.onChanged,
    this.icons,
  }) : assert(labels.length >= 2),
       assert(icons == null || icons.length == labels.length);

  final List<String> labels;
  final List<IconData>? icons;
  final int selectedIndex;
  final ValueChanged<int> onChanged;

  static const _duration = Duration(milliseconds: 220);

  @override
  Widget build(BuildContext context) {
    final count = labels.length;
    // -1 .. 1 across the segments.
    final x = count == 1 ? 0.0 : -1 + 2 * selectedIndex / (count - 1);

    return Container(
      height: 46.h,
      padding: EdgeInsets.all(4.r),
      decoration: BoxDecoration(
        color: AppColors.inputSurface,
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(color: AppColors.border),
      ),
      child: Stack(
        children: [
          AnimatedAlign(
            duration: _duration,
            curve: Curves.easeOutCubic,
            alignment: Alignment(x, 0),
            child: FractionallySizedBox(
              widthFactor: 1 / count,
              heightFactor: 1,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(9.r),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Row(
            children: [
              for (var i = 0; i < count; i++)
                Expanded(child: _segment(i, selected: i == selectedIndex)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _segment(int index, {required bool selected}) {
    final color = selected ? AppColors.primaryNavy : AppColors.textSecondary;
    return Semantics(
      button: true,
      selected: selected,
      child: GestureDetector(
        key: ValueKey('segment-$index'),
        behavior: HitTestBehavior.opaque,
        onTap: selected ? null : () => onChanged(index),
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icons != null) ...[
                Icon(icons![index], size: 16.r, color: color),
                SizedBox(width: 6.w),
              ],
              Flexible(
                child: AnimatedDefaultTextStyle(
                  duration: _duration,
                  // Same weight in both states, so the text doesn't jump.
                  style: AppTypography.label(
                    color: color,
                    fontSize: 13.sp,
                    fontWeight: FontWeight.w700,
                  ),
                  child: Text(
                    labels[index],
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
