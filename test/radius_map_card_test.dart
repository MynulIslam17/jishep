import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gps_cielo/core/models/household_model.dart';
import 'package:gps_cielo/features/home/presentation/widgets/radius_map_card.dart';

void main() {
  final households = [
    HouseholdModel(
      id: 'demo_bd_008',
      number: 1,
      residentName: 'Demo Household 008',
      address: 'Demo',
      latitude: 23.7469,
      longitude: 90.3768,
    ),
  ];

  Future<ScrollController> pumpCard(
    WidgetTester tester, {
    int radius = 10,
    int defaultHomes = 10,
    bool filtered = false,
    VoidCallback? onReset,
    List<HouseholdModel>? items,
    int? foundInRange,
    ValueChanged<int>? onRadiusChanged,
  }) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final scroll = ScrollController();
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(400, 900),
        builder: (_, _) => MaterialApp(
          home: Scaffold(
            body: ListView(
              controller: scroll,
              children: [
                RadiusMapCard(
                  radiusHomes: radius,
                  defaultRadius: defaultHomes,
                  isRadiusFiltered: filtered,
                  onResetRadius: onReset,
                  rangeMeters: 5000,
                  onRadiusChanged: onRadiusChanged,
                  households: items ?? households,
                  foundInRange: foundInRange,
                  centerLatitude: 23.7465,
                  centerLongitude: 90.376,
                  centerLabel: 'Dhanmondi, Dhaka',
                  onExpand: () {},
                ),
                const SizedBox(height: 1500),
              ],
            ),
          ),
        ),
      ),
    );
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    return scroll;
  }

  // Read through a layer that is never culled (pins leave the view on drag).
  MapCamera camera(WidgetTester tester) =>
      MapCamera.of(tester.element(find.byType(CircleLayer)));

  List<HouseholdModel> homes(int n) => [
    for (var i = 0; i < n; i++)
      HouseholdModel(
        id: 'h$i',
        number: i + 1,
        residentName: 'H$i',
        address: 'Demo',
        latitude: 23.7465 + 0.0009 * (i + 1),
        longitude: 90.376,
      ),
  ];

  testWidgets('shows the range from Settings and the household count', (
    tester,
  ) async {
    await pumpCard(tester, items: homes(10));
    expect(find.text('Around Dhanmondi, Dhaka'), findsOneWidget);
    expect(find.text('10 in range'), findsOneWidget);
    expect(
      find.text('Search range 5 km · change it in Settings'),
      findsOneWidget,
    );
    expect(find.text('Nearest 10 homes within 5 km'), findsOneWidget);
    // The circle is exactly the range.
    final circle = tester
        .widget<CircleLayer>(find.byType(CircleLayer))
        .circles
        .single;
    expect(circle.radius, 5000);
  });

  testWidgets('fewer homes in range than requested says so', (tester) async {
    await pumpCard(tester, items: homes(3));
    expect(find.text('3 homes within 5 km'), findsOneWidget);
  });

  testWidgets('the count slider covers 5-25 and reports live', (tester) async {
    final picked = <int>[];
    await pumpCard(tester, items: homes(10), onRadiusChanged: picked.add);
    final sliderFinder = find.byKey(const ValueKey('radius-slider'));
    final slider = tester.widget<Slider>(sliderFinder);
    expect(slider.min, 5);
    expect(slider.max, 25);

    final gesture = await tester.startGesture(tester.getCenter(sliderFinder));
    await gesture.moveBy(Offset(tester.getSize(sliderFinder).width * 0.3, 0));
    await tester.pump();
    expect(picked, [20]);
    await gesture.up();
  });

  testWidgets('moving the count never changes the circle', (tester) async {
    await pumpCard(tester, items: homes(10));
    final zoom = camera(tester).zoom;
    await pumpCard(tester, radius: 5, filtered: true, items: homes(5));
    final circle = tester
        .widget<CircleLayer>(find.byType(CircleLayer))
        .circles
        .single;
    expect(circle.radius, 5000);
    expect(camera(tester).zoom, zoom);
  });

  testWidgets('a filtered count offers going back to the default', (
    tester,
  ) async {
    var resets = 0;
    await pumpCard(
      tester,
      radius: 20,
      filtered: true,
      onReset: () => resets++,
      items: homes(20),
    );
    expect(find.text('Nearest 20 homes within 5 km'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('radius-reset')));
    expect(resets, 1);
    expect(find.text('Default (10)'), findsOneWidget);
  });

  testWidgets('dragging the map pans it in both directions, not the page', (
    tester,
  ) async {
    final scroll = await pumpCard(tester);
    final map = find.byType(FlutterMap);
    final start = camera(tester).center;

    await tester.drag(map, const Offset(-120, 0));
    await tester.pumpAndSettle();
    final afterHorizontal = camera(tester).center;
    expect(afterHorizontal.longitude, greaterThan(start.longitude));

    await tester.drag(map, const Offset(0, -120));
    await tester.pumpAndSettle();
    expect(camera(tester).center.latitude, lessThan(afterHorizontal.latitude));
    expect(scroll.offset, 0);
  });

  testWidgets('dragging outside the map still scrolls the page', (
    tester,
  ) async {
    final scroll = await pumpCard(tester);
    await tester.drag(find.text('Search area'), const Offset(0, -200));
    await tester.pumpAndSettle();
    expect(scroll.offset, greaterThan(0));
  });

  testWidgets('the badge counts everything in range, not just the pins', (
    tester,
  ) async {
    await pumpCard(tester, items: homes(20), foundInRange: 40);
    expect(find.text('40 in range'), findsOneWidget);
  });
}
