import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gps_cielo/core/models/household_model.dart';
import 'package:gps_cielo/shared/widgets/map/household_osm_map.dart';
import 'package:latlong2/latlong.dart';

HouseholdModel household(
  String id,
  double lat,
  double lng, {
  bool prayed = false,
}) => HouseholdModel(
  id: id,
  number: 1,
  residentName: 'Demo Household $id',
  address: 'Demo',
  latitude: lat,
  longitude: lng,
  isPrayed: prayed,
);

void main() {
  final households = [
    household('demo_bd_008', 23.7469, 90.3768),
    household('demo_bd_011', 23.7480, 90.3749, prayed: true),
  ];

  Future<void> pumpMap(
    WidgetTester tester, {
    HouseholdMapHandle? handle,
    ValueChanged<HouseholdModel>? onTap,
    List<HouseholdModel>? items,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 300,
            child: HouseholdOsmMap(
              centerLatitude: 23.7465,
              centerLongitude: 90.376,
              households: items ?? households,
              handle: handle,
              onHouseholdTap: onTap,
            ),
          ),
        ),
      ),
    );
    // Ready -> fit after layout -> rebuild at the fitted camera.
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets('shows the center pin, one pin per household and the circle', (
    tester,
  ) async {
    await pumpMap(tester);
    expect(find.byType(FlutterMap), findsOneWidget);
    expect(find.byKey(const ValueKey('center-pin')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('household-pin-demo_bd_008')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('household-pin-demo_bd_011')),
      findsOneWidget,
    );
    expect(find.byType(CircleLayer), findsOneWidget);
    expect(find.text('© OpenStreetMap contributors'), findsOneWidget);
  });

  testWidgets('tapping a pin reports that household', (tester) async {
    HouseholdModel? tapped;
    await pumpMap(tester, onTap: (h) => tapped = h);
    await tester.tap(find.byKey(const ValueKey('household-pin-demo_bd_011')));
    expect(tapped?.id, 'demo_bd_011');
  });

  testWidgets('zoom buttons change the camera zoom', (tester) async {
    final handle = HouseholdMapHandle();
    await pumpMap(tester, handle: handle);
    final camera = MapCamera.of(
      tester.element(find.byKey(const ValueKey('center-pin'))),
    );
    final before = camera.zoom;

    await handle.zoomOut();
    await tester.pump();
    final after = MapCamera.of(
      tester.element(find.byKey(const ValueKey('center-pin'))),
    ).zoom;
    expect(after, closeTo(before - 1, 0.001));
  });

  testWidgets('the default view shows the whole search circle', (tester) async {
    await pumpMap(tester);
    final camera = MapCamera.of(
      tester.element(find.byKey(const ValueKey('center-pin'))),
    );
    const center = LatLng(23.7465, 90.376);
    final radius = searchCircleRadiusMeters(23.7465, 90.376, households);
    for (final edge in searchCircleBounds(center, radius)) {
      expect(camera.visibleBounds.contains(edge), isTrue, reason: '$edge');
    }
  });

  testWidgets('a manual zoom is replaced by the full view on new households', (
    tester,
  ) async {
    final handle = HouseholdMapHandle();
    await pumpMap(tester, handle: handle);
    MapCamera camera() =>
        MapCamera.of(tester.element(find.byKey(const ValueKey('center-pin'))));
    final fitted = camera().zoom;
    await handle.zoomIn();
    await tester.pump();
    expect(camera().zoom, closeTo(fitted + 1, 0.001));

    // A new range brings more homes: back to the full circle.
    await pumpMap(
      tester,
      handle: handle,
      items: [...households, household('demo_bd_020', 23.7520, 90.3700)],
    );
    expect(camera().zoom, lessThan(fitted));
  });

  testWidgets(
    'with a range, the circle is the range and hiding pins keeps the view',
    (tester) async {
      Future<void> pump(List<HouseholdModel> items) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 400,
                height: 300,
                child: HouseholdOsmMap(
                  centerLatitude: 23.7465,
                  centerLongitude: 90.376,
                  households: items,
                  areaMeters: 900,
                ),
              ),
            ),
          ),
        );
        for (var i = 0; i < 3; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
      }

      MapCamera camera() =>
          MapCamera.of(tester.element(find.byType(CircleLayer)));
      double circle() => tester
          .widget<CircleLayer>(find.byType(CircleLayer))
          .circles
          .single
          .radius;

      await pump(households);
      final zoom = camera().zoom;
      expect(circle(), 900);

      await pump(households.take(1).toList());
      expect(circle(), 900);
      expect(camera().zoom, zoom);
    },
  );

  testWidgets('a center without households still renders', (tester) async {
    await pumpMap(tester, items: const []);
    expect(find.byKey(const ValueKey('center-pin')), findsOneWidget);
  });
}
