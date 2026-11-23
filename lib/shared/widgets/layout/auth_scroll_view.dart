import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:gps_cielo/core/constants/app_assets.dart';
import 'package:gps_cielo/core/constants/app_colors.dart';
import 'package:gps_cielo/core/constants/app_typography.dart';
import 'package:gps_cielo/core/utils/app_system_insets.dart';

/// Sign In / Sign Up layout that scrolls like the main tabs
/// ([CollapsingHeaderScrollView]): the curved navy header with the logo,
/// title and subtitle shrinks into a slim navy bar with a small title, and a
/// half-way stop snaps fully open or closed. Dragging the form closes the
/// keyboard.
class AuthScrollView extends StatefulWidget {
  const AuthScrollView({
    required this.title,
    required this.subtitle,
    required this.child,
    this.leading,
    super.key,
  });

  final String title;
  final String subtitle;

  /// Shown at the start of the bar at all times (e.g. a back button).
  final Widget? leading;
  final Widget child;

  @override
  State<AuthScrollView> createState() => _AuthScrollViewState();
}

class _AuthScrollViewState extends State<AuthScrollView> {
  final _controller = ScrollController();
  double _collapseRange = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool _onScrollEnd(ScrollEndNotification notification) {
    if (notification.depth != 0 || notification.metrics.axis != Axis.vertical) {
      return false;
    }
    final offset = notification.metrics.pixels;
    final range = _collapseRange;
    if (offset <= 0 || offset >= range) return false;
    final target = offset < range / 2 ? 0.0 : range;
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
    const toolbarHeight = 56.0;
    final metrics = _AuthHeaderMetrics();
    final minExtent = topInset + toolbarHeight;
    final maxExtent = math.max(minExtent, topInset + metrics.openHeight);
    _collapseRange = maxExtent - minExtent;

    return NotificationListener<ScrollEndNotification>(
      onNotification: _onScrollEnd,
      child: CustomScrollView(
        controller: _controller,
        physics: const AlwaysScrollableScrollPhysics(),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        slivers: [
          SliverPersistentHeader(
            pinned: true,
            delegate: _AuthHeaderDelegate(
              title: widget.title,
              subtitle: widget.subtitle,
              leading: widget.leading,
              topInset: topInset,
              toolbarHeight: toolbarHeight,
              metrics: metrics,
              minHeight: minExtent,
              maxHeight: maxExtent,
            ),
          ),
          SliverToBoxAdapter(child: widget.child),
          SliverToBoxAdapter(
            child: SizedBox(height: AppSystemInsets.bottom(context)),
          ),
        ],
      ),
    );
  }
}

/// Sizes of the open header (below the status bar).
class _AuthHeaderMetrics {
  final double top = 20.h;
  final double logoWidth = 52.w;
  final double logoHeight = 62.h;
  final double logoGap = 16.h;
  final double titleSize = 24.sp;
  final double titleHeight = 1.25;
  final double subtitleGap = 4.h;
  final double subtitleSize = 14.sp;
  final double subtitleHeight = 1.4;
  final double bottom = 28.h;

  double get openHeight =>
      top +
      logoHeight +
      logoGap +
      titleSize * titleHeight +
      subtitleGap +
      subtitleSize * subtitleHeight +
      bottom;
}

class _AuthHeaderDelegate extends SliverPersistentHeaderDelegate {
  _AuthHeaderDelegate({
    required this.title,
    required this.subtitle,
    required this.leading,
    required this.topInset,
    required this.toolbarHeight,
    required this.metrics,
    required this.minHeight,
    required this.maxHeight,
  });

  final String title;
  final String subtitle;
  final Widget? leading;
  final double topInset;
  final double toolbarHeight;
  final _AuthHeaderMetrics metrics;
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
    final radius = 28.r * (1 - t);

    return Material(
      color: AppColors.primaryNavy,
      elevation: t >= 1 ? 3 : 0,
      shadowColor: Colors.black.withValues(alpha: 0.25),
      borderRadius: BorderRadius.vertical(bottom: Radius.circular(radius)),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Logo, title and subtitle, anchored to the bottom so they slide
          // up and fade as the header shrinks.
          Positioned(
            left: 24.w,
            right: 24.w,
            bottom: metrics.bottom,
            child: IgnorePointer(
              child: Opacity(
                opacity: largeOpacity,
                child: Column(
                  key: const ValueKey('auth-large-header'),
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SvgPicture.asset(
                      AppAssets.logoMark,
                      width: metrics.logoWidth,
                      height: metrics.logoHeight,
                      fit: BoxFit.contain,
                    ),
                    SizedBox(height: metrics.logoGap),
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: AppTypography.heading(
                        color: AppColors.textWhite,
                        fontSize: metrics.titleSize,
                        fontWeight: FontWeight.w700,
                        height: metrics.titleHeight,
                      ),
                    ),
                    SizedBox(height: metrics.subtitleGap),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: AppTypography.body(
                        color: AppColors.textWhite.withValues(alpha: 0.75),
                        fontSize: metrics.subtitleSize,
                      ).copyWith(height: metrics.subtitleHeight),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Slim bar: back button and, once collapsed, a small title.
          Positioned(
            top: topInset,
            left: 16.w,
            right: 16.w,
            height: toolbarHeight,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Opacity(
                  opacity: compactOpacity,
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 48.w),
                    child: Text(
                      title,
                      key: const ValueKey('auth-compact-title'),
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
                if (leading != null)
                  Align(alignment: Alignment.centerLeft, child: leading),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  bool shouldRebuild(_AuthHeaderDelegate old) =>
      old.title != title ||
      old.subtitle != subtitle ||
      old.leading != leading ||
      old.topInset != topInset ||
      old.minHeight != minHeight ||
      old.maxHeight != maxHeight;
}
