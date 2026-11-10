import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gps_cielo/core/models/household_model.dart';
import 'package:gps_cielo/features/follow_up/presentation/controllers/follow_up_controller.dart';
import 'package:gps_cielo/features/follow_up/presentation/widgets/follow_up_household_item.dart';
import 'package:gps_cielo/shared/widgets/layout/collapsing_header_scroll_view.dart';

Widget phone(Widget child) => ScreenUtilInit(
  designSize: const Size(400, 800),
  builder: (_, _) => MaterialApp(home: Scaffold(body: child)),
);

void usePhoneSize(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.7;
  addTearDown(tester.view.reset);
}

double opacityOf(WidgetTester tester, Finder finder) => tester
    .widget<Opacity>(
      find.ancestor(of: finder, matching: find.byType(Opacity)).first,
    )
    .opacity;

void main() {
  Widget screen({ScrollController? controller}) => phone(
    CollapsingHeaderScrollView(
      title: 'Follow-up',
      controller: controller,
      subtitle: const Text('Everyone you prayed for'),
      header: const Text('legend'),
      pinnedHeight: 48,
      pinned: const Center(child: Text('TABS')),
      slivers: [
        SliverList.builder(
          itemCount: 60,
          itemBuilder: (_, i) => SizedBox(height: 60, child: Text('row $i')),
        ),
      ],
    ),
  );

  testWidgets('at rest the large title sits right under the status bar', (
    tester,
  ) async {
    usePhoneSize(tester);
    await tester.pumpWidget(screen());
    final compact = find.byKey(const ValueKey('compact-title'));
    expect(opacityOf(tester, compact), 0);
    // No empty bar above the title: it starts within ~70 px of the top.
    final titleTop = tester
        .getTopLeft(
          find.descendant(
            of: find.byKey(const ValueKey('large-header')),
            matching: find.text('Follow-up'),
          ),
        )
        .dy;
    expect(titleTop, lessThan(70));
  });

  testWidgets('collapses into a solid bar; the tabs stick below it', (
    tester,
  ) async {
    usePhoneSize(tester);
    await tester.pumpWidget(screen());
    final compact = find.byKey(const ValueKey('compact-title'));
    final tabsTop = tester.getTopLeft(find.text('TABS')).dy;

    await tester.drag(find.text('row 3'), const Offset(0, -800));
    await tester.pumpAndSettle();
    expect(opacityOf(tester, compact), 1);
    final pinnedTop = tester.getTopLeft(find.text('TABS')).dy;
    expect(pinnedTop, lessThan(tabsTop));

    await tester.drag(find.text('row 20'), const Offset(0, -800));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('TABS')).dy, closeTo(pinnedTop, 0.5));
    // The header background never turns see-through.
    final bar = tester.widget<Material>(
      find.ancestor(of: compact, matching: find.byType(Material)).first,
    );
    expect(bar.color, isNot(Colors.transparent));
  });

  testWidgets('a small scroll snaps the header back open', (tester) async {
    usePhoneSize(tester);
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(screen(controller: controller));

    await tester.drag(find.text('row 1'), const Offset(0, -15));
    await tester.pumpAndSettle();
    expect(controller.offset, 0);
  });

  testWidgets('scrolling past half way snaps it fully closed', (tester) async {
    usePhoneSize(tester);
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(screen(controller: controller));
    final compact = find.byKey(const ValueKey('compact-title'));

    // Find the collapse distance, then stop a little past half of it.
    await tester.drag(find.text('row 3'), const Offset(0, -2000));
    await tester.pumpAndSettle();
    controller.jumpTo(0);
    await tester.pumpAndSettle();

    await tester.drag(find.text('row 1'), const Offset(0, -45));
    await tester.pumpAndSettle();
    expect(controller.offset, greaterThan(40));
    expect(opacityOf(tester, compact), 1);
  });

  testWidgets('header icon button shows a badge only when there is one', (
    tester,
  ) async {
    usePhoneSize(tester);
    await tester.pumpWidget(
      phone(
        Row(
          children: [
            HeaderIconButton(
              icon: Icons.notifications,
              onPressed: () {},
              badge: 3,
            ),
            HeaderIconButton(icon: Icons.settings, onPressed: () {}),
          ],
        ),
      ),
    );
    expect(find.text('3'), findsOneWidget);
    expect(find.text('0'), findsNothing);
  });

  group('Follow-up item', () {
    final item = HouseholdModel(
      id: 'h1',
      number: 1,
      residentName: 'Demo Household 101',
      address: 'Demo location 101, Demra (synthetic)',
      isPrayed: true,
    );

    Future<void> pump(WidgetTester tester, {required bool nearHome}) {
      usePhoneSize(tester);
      return tester.pumpWidget(
        phone(
          FollowUpHouseholdItem(
            item: item,
            selectedTab: FollowUpTab.all,
            nearHome: nearHome,
            onUpdated: (_) {},
          ),
        ),
      );
    }

    testWidgets('marks households outside the neighborhood', (tester) async {
      await pump(tester, nearHome: false);
      expect(find.text('Outside your neighborhood'), findsOneWidget);
    });

    testWidgets('no label for households near home', (tester) async {
      await pump(tester, nearHome: true);
      expect(find.text('Outside your neighborhood'), findsNothing);
    });
  });
}
