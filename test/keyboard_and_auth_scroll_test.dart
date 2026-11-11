import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gps_cielo/core/utils/system_ui_config.dart';
import 'package:gps_cielo/shared/widgets/layout/auth_scroll_view.dart';

const _keyboard = 300.0;

void main() {
  /// The app shell (SystemUiConfig.wrapApp) around [home].
  Future<void> pumpApp(WidgetTester tester, Widget home) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (_, _) =>
            MaterialApp(builder: SystemUiConfig.wrapApp, home: home),
      ),
    );
  }

  /// Simulates the system keyboard opening or closing.
  Future<void> setKeyboard(WidgetTester tester, double height) async {
    tester.view.viewInsets = FakeViewPadding(bottom: height * 3);
    await tester.pump();
  }

  bool fieldFocused(WidgetTester tester, Key key) => tester
      .widget<EditableText>(
        find.descendant(
          of: find.byKey(key),
          matching: find.byType(EditableText),
        ),
      )
      .focusNode
      .hasFocus;

  group('keyboard Done bar', () {
    Widget form() => const Scaffold(
      body: Column(
        children: [
          // A number pad and a multi-line field have no return key.
          TextField(
            key: ValueKey('amount'),
            keyboardType: TextInputType.number,
          ),
          TextField(key: ValueKey('notes'), maxLines: null),
          Expanded(child: SizedBox.expand(key: ValueKey('empty-space'))),
        ],
      ),
    );

    testWidgets('appears on the keyboard and Done closes it', (tester) async {
      await pumpApp(tester, form());
      expect(find.byKey(const ValueKey('keyboard-done-bar')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('amount')));
      await setKeyboard(tester, _keyboard);
      expect(fieldFocused(tester, const ValueKey('amount')), isTrue);

      final bar = find.byKey(const ValueKey('keyboard-done-bar'));
      expect(bar, findsOneWidget);
      // Sits right on top of the keyboard.
      expect(
        tester.getBottomLeft(bar).dy,
        closeTo(tester.view.physicalSize.height / 3 - _keyboard, 0.5),
      );

      await tester.tap(find.text('Done'));
      await tester.pump();
      expect(fieldFocused(tester, const ValueKey('amount')), isFalse);
      await setKeyboard(tester, 0);
      expect(bar, findsNothing);
    });

    testWidgets('content is laid out above the bar', (tester) async {
      await pumpApp(tester, form());
      await tester.tap(find.byKey(const ValueKey('notes')));
      await setKeyboard(tester, _keyboard);

      final barTop = tester
          .getTopLeft(find.byKey(const ValueKey('keyboard-done-bar')))
          .dy;
      final contentBottom = tester
          .getBottomLeft(find.byKey(const ValueKey('empty-space')))
          .dy;
      expect(contentBottom, lessThanOrEqualTo(barTop + 0.5));
    });

    testWidgets('tapping outside a field closes the keyboard', (tester) async {
      await pumpApp(tester, form());
      await tester.tap(find.byKey(const ValueKey('notes')));
      await setKeyboard(tester, _keyboard);
      expect(fieldFocused(tester, const ValueKey('notes')), isTrue);

      await tester.tap(find.byKey(const ValueKey('empty-space')));
      await tester.pump();
      expect(fieldFocused(tester, const ValueKey('notes')), isFalse);
    });

    testWidgets('tapping another field keeps the keyboard', (tester) async {
      await pumpApp(tester, form());
      await tester.tap(find.byKey(const ValueKey('amount')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('notes')));
      await tester.pump();
      expect(fieldFocused(tester, const ValueKey('notes')), isTrue);
    });
  });

  group('AuthScrollView', () {
    Widget screen() => Scaffold(
      body: AuthScrollView(
        title: 'Welcome Back',
        subtitle: 'Sign in to your account',
        leading: const Icon(Icons.chevron_left, key: ValueKey('back')),
        child: Column(
          children: [
            const TextField(key: ValueKey('email')),
            for (var i = 0; i < 12; i++)
              SizedBox(height: 80, child: Text('$i')),
          ],
        ),
      ),
    );

    double opacityOf(WidgetTester tester, String key) => tester
        .widget<Opacity>(
          find
              .ancestor(
                of: find.byKey(ValueKey(key)),
                matching: find.byType(Opacity),
              )
              .first,
        )
        .opacity;

    testWidgets('header collapses into a slim bar like the main tabs', (
      tester,
    ) async {
      await pumpApp(tester, screen());
      expect(opacityOf(tester, 'auth-large-header'), 1);
      expect(opacityOf(tester, 'auth-compact-title'), 0);
      expect(find.byKey(const ValueKey('back')), findsOneWidget);

      await tester.drag(find.byType(CustomScrollView), const Offset(0, -400));
      await tester.pumpAndSettle();
      expect(opacityOf(tester, 'auth-large-header'), 0);
      expect(opacityOf(tester, 'auth-compact-title'), 1);
      expect(find.byKey(const ValueKey('back')).hitTestable(), findsOneWidget);
    });

    testWidgets('a half-way stop snaps the header open', (tester) async {
      await pumpApp(tester, screen());
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -20));
      await tester.pumpAndSettle();
      final scroll = tester.state<ScrollableState>(find.byType(Scrollable).first);
      expect(scroll.position.pixels, 0);
    });

    testWidgets('dragging the form closes the keyboard', (tester) async {
      await pumpApp(tester, screen());
      await tester.tap(find.byKey(const ValueKey('email')));
      await setKeyboard(tester, _keyboard);
      expect(fieldFocused(tester, const ValueKey('email')), isTrue);

      await tester.drag(find.text('0'), const Offset(0, -60));
      await tester.pumpAndSettle();
      expect(fieldFocused(tester, const ValueKey('email')), isFalse);
    });
  });
}
