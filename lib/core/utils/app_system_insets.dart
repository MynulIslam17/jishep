import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

abstract final class AppSystemInsets {
  static const double androidNavFallback = 48;

  static double bottom(BuildContext context) =>
      MediaQuery.viewPaddingOf(context).bottom;

  static double top(BuildContext context) {
    final mq = MediaQuery.of(context);
    var top = math.max(mq.viewPadding.top, mq.padding.top);
    final view = View.maybeOf(context);
    if (view != null) {
      final dpr = view.devicePixelRatio;
      top = math.max(top, view.padding.top / dpr);
      top = math.max(top, view.viewPadding.top / dpr);
    }
    return top;
  }

  static double keyboard(BuildContext context) =>
      MediaQuery.viewInsetsOf(context).bottom;

  static double resolveRawBottom(BuildContext context) {
    final mq = MediaQuery.of(context);
    var bottom = math.max(mq.viewPadding.bottom, mq.padding.bottom);

    final view = View.maybeOf(context);
    if (view != null) {
      final dpr = view.devicePixelRatio;
      bottom = math.max(bottom, view.padding.bottom / dpr);
      bottom = math.max(bottom, view.viewPadding.bottom / dpr);
    }

    if (bottom < 1 && defaultTargetPlatform == TargetPlatform.android) {
      bottom = androidNavFallback;
    }
    return bottom;
  }

  static double bottomContent(
    BuildContext context, {
    bool includeKeyboard = true,
  }) {
    final system = bottom(context);
    if (!includeKeyboard) return system;
    return math.max(system, keyboard(context));
  }
}
