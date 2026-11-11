import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:gps_cielo/core/constants/app_colors.dart';
import 'package:gps_cielo/core/constants/app_typography.dart';
import 'package:gps_cielo/core/utils/app_system_insets.dart';

/// The shared "large title" layout of the main tabs.
///
///  * One navy header: at rest it shows the large [title], a one-line
///    [subtitle] and an optional one-line [header] row (e.g. a legend) right
///    under the status bar. Scrolling shrinks it into a slim bar with a small
///    title; the background stays solid navy the whole time.
///  * When the user stops half-way, the header snaps fully open or closed.
///  * An optional [pinned] strip (tabs, a progress summary) sticks below the
///    bar, with a soft shadow once content scrolls under it.
///  * [slivers] are the scrolling body.
class CollapsingHeaderScrollView extends StatefulWidget {
  const CollapsingHeaderScrollView({
    required this.title,
    required this.slivers,
    this.subtitle,
    this.header,
    this.leading,
    this.actions = const [],
    this.pinned,
    this.pinnedHeight = 0,
    this.pinnedColor = AppColors.background,
    this.onRefresh,
    this.controller,
    super.key,
  });

  final String title;

  /// One line under the title (ellipsized when long).
  final Widget? subtitle;

  /// One extra line under the subtitle, such as a legend.
  final Widget? header;

  /// Shown at the start of the slim bar at all times, e.g. a back button on
  /// pushed screens.
  final Widget? leading;
  final List<Widget> actions;

  /// Sticks below the bar; [pinnedHeight] is its height in logical px.
  final Widget? pinned;
  final double pinnedHeight;
  final Color pinnedColor;

  final List<Widget> slivers;
  final Future<void> Function()? onRefresh;
  final ScrollController? controller;

  @override
  State<CollapsingHeaderScrollView> createState() =>
      _CollapsingHeaderScrollViewState();
}

class _CollapsingHeaderScrollViewState
    extends State<CollapsingHeaderScrollView> {
  ScrollController? _ownController;

  ScrollController get _controller =>
      widget.controller ?? (_ownController ??= ScrollController());

  /// How far the header collapses, set on each build.
  double _collapseRange = 0;

  @override
  void dispose() {
    _ownController?.dispose();
    super.dispose();
  }

  /// Settles a half-collapsed header fully open or closed.
  bool _onScrollEnd(ScrollEndNotification notification) {
    if (notification.depth != 0 || notification.metrics.axis != Axis.vertical) {
      return false;
    }
    final offset = notification.metrics.pixels;
    final range = _collapseRange;
    if (offset <= 0 || offset >= range) return false;
    final target = offset < range / 2 ? 0.0 : range;
    // After the current scroll activity has fully ended.
    Future.microtask(() {
      if (!mounted || !_controller.hasClients) return;
      _controller.animateTo(
        target,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    });
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final topInset = AppSystemInsets.top(context);
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final toolbarHeight = 56.0;

    // Height of the large title block (title, subtitle, header line).
    final titleHeight = 30.sp * 1.25 * textScale;
    final lineHeight = 13.sp * 1.45 * textScale;
    final blockHeight =
        titleHeight +
        (widget.subtitle != null ? 4 + lineHeight : 0) +
        (widget.header != null ? 10 + lineHeight + 2 : 0);
    // With a leading button the large title sits below the slim bar.
    final topPadding = widget.leading != null ? toolbarHeight : 8.0;
    final bottomPadding = 18.h;

    final minExtent = topInset + toolbarHeight;
    final maxExtent = math.max(
      minExtent,
      topInset + topPadding + blockHeight + bottomPadding,
    );
    _collapseRange = maxExtent - minExtent;

    final view = NotificationListener<ScrollEndNotification>(
      onNotification: _onScrollEnd,
      child: CustomScrollView(
        controller: _controller,
        physics: const AlwaysScrollableScrollPhysics(),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        slivers: [
          SliverPersistentHeader(
            pinned: true,
            delegate: _LargeTitleHeaderDelegate(
              title: widget.title,
              subtitle: widget.subtitle,
              header: widget.header,
              leading: widget.leading,
              actions: widget.actions,
              topInset: topInset,
              toolbarHeight: toolbarHeight,
              bottomPadding: bottomPadding,
              minHeight: minExtent,
              maxHeight: maxExtent,
            ),
          ),
          if (widget.pinned != null)
            SliverPersistentHeader(
              pinned: true,
              delegate: _PinnedStripDelegate(
                height: widget.pinnedHeight,
                color: widget.pinnedColor,
                child: widget.pinned!,
              ),
            ),
          ...widget.slivers,
          SliverToBoxAdapter(
            child: SizedBox(height: 24.h + AppSystemInsets.bottom(context)),
          ),
        ],
      ),
    );

    final onRefresh = widget.onRefresh;
    if (onRefresh == null) return view;
    return RefreshIndicator(
      onRefresh: onRefresh,
      edgeOffset: maxExtent + widget.pinnedHeight,
      color: AppColors.primaryNavy,
      child: view,
    );
  }
}

class _LargeTitleHeaderDelegate extends SliverPersistentHeaderDelegate {
  _LargeTitleHeaderDelegate({
    required this.title,
    required this.subtitle,
    required this.header,
    required this.leading,
    required this.actions,
    required this.topInset,
    required this.toolbarHeight,
    required this.bottomPadding,
    required this.minHeight,
    required this.maxHeight,
  });

  final String title;
  final Widget? subtitle;
  final Widget? header;
  final Widget? leading;
  final List<Widget> actions;
  final double topInset;
  final double toolbarHeight;
  final double bottomPadding;
  final double minHeight;
  final double maxHeight;

  @override
  double get minExtent => minHeight;

  @override
  double get maxExtent => maxHeight;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final range = maxHeight - minHeight;
    // 0 = fully open, 1 = fully collapsed.
    final t = range <= 0 ? 1.0 : (shrinkOffset / range).clamp(0.0, 1.0);
    final largeOpacity = (1 - t * 1.8).clamp(0.0, 1.0);
    final compactOpacity = ((t - 0.65) / 0.35).clamp(0.0, 1.0);

    return Material(
      color: AppColors.primaryNavy,
      elevation: t >= 1 ? 3 : 0,
      shadowColor: Colors.black.withValues(alpha: 0.25),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Large title, anchored to the bottom so it slides up as the
          // header shrinks.
          Positioned(
            left: 20.w,
            right: 20.w,
            bottom: bottomPadding,
            child: IgnorePointer(
              ignoring: largeOpacity == 0,
              child: Opacity(
                opacity: largeOpacity,
                child: Column(
                  key: const ValueKey('large-header'),
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.heading(
                        color: AppColors.textWhite,
                        fontSize: 26.sp,
                        fontWeight: FontWeight.w800,
                        height: 1.2,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 4),
                      DefaultTextStyle.merge(
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.body(
                          color: AppColors.textWhite.withValues(alpha: 0.78),
                          fontSize: 13.sp,
                        ),
                        child: subtitle!,
                      ),
                    ],
                    if (header != null) ...[
                      const SizedBox(height: 10),
                      header!,
                    ],
                  ],
                ),
              ),
            ),
          ),
          // Slim bar: small title (once collapsed) and actions.
          Positioned(
            top: topInset,
            left: 20.w,
            right: 12.w,
            height: toolbarHeight,
            child: Row(
              children: [
                if (leading != null) ...[leading!, SizedBox(width: 12.w)],
                Expanded(
                  child: Opacity(
                    opacity: compactOpacity,
                    child: Text(
                      title,
                      key: const ValueKey('compact-title'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.heading(
                        color: AppColors.textWhite,
                        fontSize: 17.sp,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                ...actions,
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  bool shouldRebuild(_LargeTitleHeaderDelegate old) =>
      old.title != title ||
      old.subtitle != subtitle ||
      old.header != header ||
      old.leading != leading ||
      old.actions != actions ||
      old.topInset != topInset ||
      old.minHeight != minHeight ||
      old.maxHeight != maxHeight;
}

class _PinnedStripDelegate extends SliverPersistentHeaderDelegate {
  _PinnedStripDelegate({
    required this.height,
    required this.color,
    required this.child,
  });

  final double height;
  final Color color;
  final Widget child;

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        boxShadow: overlapsContent
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
      ),
      child: SizedBox.expand(child: child),
    );
  }

  @override
  bool shouldRebuild(_PinnedStripDelegate old) =>
      old.height != height || old.color != color || old.child != child;
}

/// A round icon button for a header (e.g. notifications) with an optional
/// unread badge.
class HeaderIconButton extends StatelessWidget {
  const HeaderIconButton({
    required this.icon,
    required this.onPressed,
    this.badge = 0,
    this.tooltip,
    this.dark = true,
    super.key,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final int badge;
  final String? tooltip;

  /// True on the navy bar (light icon), false on a white bar.
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Material(
          color: dark
              ? Colors.white.withValues(alpha: 0.12)
              : AppColors.inputSurface,
          shape: const CircleBorder(),
          child: IconButton(
            tooltip: tooltip,
            constraints: BoxConstraints.tight(Size.square(38.r)),
            padding: EdgeInsets.zero,
            icon: Icon(
              icon,
              size: 20.r,
              color: dark ? AppColors.textWhite : AppColors.primaryNavy,
            ),
            onPressed: onPressed,
          ),
        ),
        if (badge > 0)
          Positioned(
            top: -2,
            right: -2,
            child: Container(
              constraints: BoxConstraints(minWidth: 17.r, minHeight: 17.r),
              padding: EdgeInsets.symmetric(horizontal: 4.r),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.danger,
                borderRadius: BorderRadius.circular(9.r),
                border: Border.all(
                  color: dark ? AppColors.primaryNavy : Colors.white,
                  width: 1.5,
                ),
              ),
              child: Text(
                badge > 99 ? '99+' : '$badge',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 9.sp,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// A rounded "notice" card: icon, title, message and optional actions. Used
/// for empty and status states.
class AppNoticeCard extends StatelessWidget {
  const AppNoticeCard({
    required this.icon,
    required this.title,
    required this.message,
    this.actions = const [],
    this.highlight = false,
    super.key,
  });

  final IconData icon;
  final String title;
  final String message;
  final List<Widget> actions;

  /// Gold styling for good news (e.g. a completed cycle).
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(16.r),
      decoration: BoxDecoration(
        color: highlight ? const Color(0xFFFFF8E1) : AppColors.surface,
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(
          color: highlight ? AppColors.primaryGold : AppColors.border,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36.r,
            height: 36.r,
            decoration: BoxDecoration(
              color: highlight
                  ? AppColors.primaryGold.withValues(alpha: 0.18)
                  : AppColors.primaryNavy.withValues(alpha: 0.07),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 19.r, color: AppColors.primaryNavy),
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
                    fontSize: 14.5.sp,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(height: 4.h),
                Text(
                  message,
                  style: AppTypography.body(
                    color: AppColors.textSecondary,
                    fontSize: 12.5.sp,
                    height: 1.4,
                  ),
                ),
                if (actions.isNotEmpty) ...[
                  SizedBox(height: 12.h),
                  Wrap(spacing: 8.w, runSpacing: 8.h, children: actions),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
