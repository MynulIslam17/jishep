import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:gps_cielo/core/constants/app_colors.dart';

/// App-wide keyboard closing, so the keyboard can always be put away:
///
///  * A "Done" bar sits on top of the keyboard whenever it is open. Number
///    pads and multi-line fields (notes, support messages) have no return
///    key, so this is the only button that closes them.
///  * Tapping anywhere outside a text field closes the keyboard.
///
/// [gapBelowContent] is how far above the bottom of the screen the app
/// content already ends (the system navigation inset reserved by
/// [SystemUiConfig.wrapApp]); the content is pushed up only by what the bar
/// needs beyond that.
class KeyboardDoneBar extends StatelessWidget {
  const KeyboardDoneBar({
    required this.child,
    this.gapBelowContent = 0,
    super.key,
  });

  static const double height = 44;

  final Widget child;
  final double gapBelowContent;

  static void dismiss() => FocusManager.instance.primaryFocus?.unfocus();

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final keyboard = media.viewInsets.bottom;
    final open = keyboard > 0;

    // Tap outside a field: text fields and buttons win the tap themselves,
    // so this only fires on empty space.
    Widget content = GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: dismiss,
      child: child,
    );
    if (open) {
      final extra = math.max(0.0, height - gapBelowContent);
      content = MediaQuery(
        data: media.copyWith(
          viewInsets: media.viewInsets.copyWith(bottom: keyboard + extra),
        ),
        child: content,
      );
    }

    return Stack(
      children: [
        Positioned.fill(child: content),
        if (open)
          Positioned(
            left: 0,
            right: 0,
            bottom: keyboard,
            height: height,
            child: const _Bar(),
          ),
      ],
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar();

  @override
  Widget build(BuildContext context) {
    return Material(
      key: const ValueKey('keyboard-done-bar'),
      color: const Color(0xFFF1F3F6),
      child: DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        child: Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: const EdgeInsets.only(right: 8),
            child: TextButton(
              onPressed: KeyboardDoneBar.dismiss,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.primaryNavy,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                minimumSize: const Size(64, 36),
              ),
              child: const Text(
                'Done',
                semanticsLabel: 'Done, close keyboard',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
