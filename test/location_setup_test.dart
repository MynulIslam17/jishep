import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:gps_cielo/core/data/geo_search.dart';
import 'package:gps_cielo/core/data/household_repository.dart';
import 'package:gps_cielo/core/models/user_model.dart';
import 'package:gps_cielo/core/services/address_suggestion_service.dart';
import 'package:gps_cielo/core/services/location_service.dart';
import 'package:gps_cielo/features/auth/domain/services/auth_service.dart';
import 'package:gps_cielo/features/auth/presentation/controllers/auth_controller.dart';
import 'package:gps_cielo/features/auth/presentation/controllers/location_setup_controller.dart';
import 'package:gps_cielo/features/auth/presentation/pages/location_setup_screen.dart';

import 'support/synthetic_households.dart';

class _Households implements HouseholdRepository {
  /// [count] households going north from any searched point, [spacing]
  /// degrees (~100 m by default) apart.
  _Households(this.count, {this.spacing = 0.000899});

  final int count;
  final double spacing;
  final calls = <double>[];
  bool fail = false;

  @override
  GeoSearch geoSearch({
    required double latitude,
    required double longitude,
    required double radiusKm,
  }) {
    calls.add(radiusKm);
    final index = IndexedHouseholds([
      for (var i = 0; i < count; i++)
        (id: 'demo_$i', lat: latitude + spacing * (i + 1), lng: longitude),
    ]);
    return GeoSearch(
      query: (prefix, {required limit, startAfter}) async {
        if (fail) throw Exception('offline');
        return index.query(prefix, limit: limit, startAfter: startAfter);
      },
      latitude: latitude,
      longitude: longitude,
      maxMeters: radiusKm * 1000,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Location implements LocationService {
  ResolvedLocation? gps;
  LocationException? gpsError;

  @override
  Future<ResolvedLocation> currentLocation() async {
    if (gpsError != null) throw gpsError!;
    return gps!;
  }

  @override
  Future<ResolvedLocation> resolveAddress(String address) async =>
      ResolvedLocation(address: address, latitude: 1, longitude: 2);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Service implements AuthService {
  Map<String, Object>? saved;

  @override
  Future<void> updateLocation({
    required String address,
    required double latitude,
    required double longitude,
    required double searchRadiusKm,
    required int dailyPrayerTarget,
  }) async {
    saved = {
      'address': address,
      'latitude': latitude,
      'longitude': longitude,
      'searchRadiusKm': searchRadiusKm,
      'dailyPrayerTarget': dailyPrayerTarget,
    };
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Auth extends GetxController implements AuthController {
  _Auth(UserModel user) {
    currentUser.value = user;
  }

  @override
  final currentUser = Rxn<UserModel>();

  @override
  void updateUser(UserModel user) => currentUser.value = user;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const demra = AddressSuggestion(
  title: 'Demra',
  subtitle: 'Dhaka, Bangladesh',
  latitude: 23.721,
  longitude: 90.483,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => Get.testMode = true);
  tearDown(Get.reset);

  late _Households households;
  late _Location location;
  late _Service service;
  late _Auth auth;

  Future<LocationSetupController> make({UserModel? user}) async {
    households = _Households(40);
    location = _Location();
    service = _Service();
    auth = _Auth(
      user ?? UserModel(id: 'u1', fullName: 'N', email: 'n@example.com'),
    );
    final c = LocationSetupController(
      service,
      auth,
      location,
      households,
      previewDebounce: Duration.zero,
    )..onInit();
    return c;
  }

  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 5));

  group('LocationSetupController', () {
    test('picking an address loads the households in range', () async {
      final c = await make();
      expect(c.hasLocation, isFalse);
      c.selectSuggestion(demra);
      await settle();
      expect(c.previewHouseholds.length, 40); // 5 km default → all 40
      expect(c.previewSummary, '40 neighbors within 5 km');
      expect(c.cycleDays, 8); // 40 / 5 a day
    });

    test('changing the range refreshes the preview', () async {
      final c = await make();
      c.selectSuggestion(demra);
      await settle();
      c.setRange(1);
      await settle();
      expect(households.calls.last, 1);
      expect(c.previewHouseholds.length, 10);
      expect(c.previewSummary, '10 neighbors within 1 km');
      c.setDailyGoal(10);
      expect(c.cycleDays, 1);
    });

    test('a dense range reads only the nearest 200 and shows "200+"', () async {
      final c = await make();
      // 1000 households ~10 m apart: all within 5 km.
      final dense = _Households(1000, spacing: 0.0000899);
      final d = LocationSetupController(
        service,
        auth,
        location,
        dense,
        previewDebounce: Duration.zero,
      )..onInit();
      d.selectSuggestion(demra);
      await settle();
      expect(d.previewHouseholds.length, 200);
      expect(d.previewHouseholds.first.id, 'demo_0'); // nearest first
      expect(d.previewHouseholds.last.id, 'demo_199');
      expect(d.previewComplete.value, isFalse);
      expect(d.previewSummary, '200+ neighbors within 5 km');
      c.onClose();
      d.onClose();
    });

    test('editing the address clears the pick and the map', () async {
      final c = await make();
      c.addressController.text = demra.fullAddress;
      c.selectSuggestion(demra);
      await settle();
      c.addressController.text = 'Demra, Dh';
      await settle();
      expect(c.hasLocation, isFalse);
      expect(c.previewHouseholds, isEmpty);
    });

    test('a failed preview shows retry, and retry recovers', () async {
      final c = await make();
      households.fail = true;
      c.selectSuggestion(demra);
      await settle();
      expect(c.previewError.value, isTrue);
      households.fail = false;
      c.retryPreview();
      await settle();
      expect(c.previewError.value, isFalse);
      expect(c.previewHouseholds, isNotEmpty);
    });

    test('GPS errors are kept for the inline fix', () async {
      final c = await make();
      location.gpsError = const LocationException(
        LocationFailure.permissionDeniedForever,
        'Location permission is off.',
      );
      await c.useCurrentLocation();
      expect(
        c.locationError.value?.reason,
        LocationFailure.permissionDeniedForever,
      );
      expect(c.isLocating.value, isFalse);

      location
        ..gpsError = null
        ..gps = const ResolvedLocation(
          address: 'Demra, Dhaka',
          latitude: 23.72,
          longitude: 90.48,
          source: LocationSource.gps,
        );
      await c.useCurrentLocation();
      expect(c.locationError.value, isNull);
      expect(c.hasLocation, isTrue);
      expect(c.addressController.text, 'Demra, Dhaka');
    });

    test('saves home, range and daily goal together', () async {
      final c = await make();
      c.addressController.text = demra.fullAddress;
      c.selectSuggestion(demra);
      c.setRange(2);
      c.setDailyGoal(10);
      await c.confirmLocation();
      expect(service.saved, {
        'address': 'Demra, Dhaka, Bangladesh',
        'latitude': 23.721,
        'longitude': 90.483,
        'searchRadiusKm': 2.0,
        'dailyPrayerTarget': 10,
      });
      expect(auth.currentUser.value?.searchRadiusKm, 2);
      expect(auth.currentUser.value?.dailyPrayerTarget, 10);
    });

    test('a typed address without a pick is looked up on save', () async {
      final c = await make();
      c.addressController.text = 'Road 5, Demra';
      await c.confirmLocation();
      expect(service.saved?['address'], 'Road 5, Demra');
      expect(service.saved?['latitude'], 1);
    });

    test('nothing is saved without an address', () async {
      final c = await make();
      await c.confirmLocation();
      expect(service.saved, isNull);
    });

    test('a saved home is shown again with its preferences', () async {
      final c = await make(
        user: UserModel(
          id: 'u1',
          fullName: 'N',
          email: 'n@example.com',
          address: 'Demra, Dhaka',
          latitude: 23.721,
          longitude: 90.483,
          searchRadiusKm: 2,
          dailyPrayerTarget: 10,
        ),
      );
      await settle();
      expect(c.hasLocation, isTrue);
      expect(c.rangeKm.value, 2);
      expect(c.dailyGoal.value, 10);
      expect(c.previewHouseholds.length, 20);
    });
  });

  group('LocationSetupScreen', () {
    Future<void> pump(WidgetTester tester, LocationSetupController c) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.7;
      addTearDown(tester.view.reset);
      Get.put<LocationSetupController>(c);
      await tester.pumpWidget(
        ScreenUtilInit(
          designSize: const Size(400, 800),
          builder: (_, _) => const GetMaterialApp(home: LocationSetupScreen()),
        ),
      );
      await tester.pump();
    }

    testWidgets('without a home: placeholder map and guidance', (tester) async {
      final c = await tester.runAsync(make);
      await pump(tester, c!);
      expect(find.byKey(const ValueKey('map-placeholder')), findsOneWidget);
      expect(
        find.text('Choose your home to see your neighbors'),
        findsOneWidget,
      );
      expect(find.text('Continue'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('goal-5')),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.byKey(const ValueKey('range-5.0')), findsOneWidget);
      expect(find.byKey(const ValueKey('goal-5')), findsOneWidget);
      // The header collapsed; the summary strip stays pinned.
      expect(find.byKey(const ValueKey('setup-summary')), findsOneWidget);
    });

    testWidgets('with a home: real map, count and save button', (tester) async {
      final c = await tester.runAsync(make);
      c!.selectSuggestion(demra);
      await tester.runAsync(settle);
      await pump(tester, c);
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(find.byKey(const ValueKey('setup-map')), findsOneWidget);
      expect(find.byKey(const ValueKey('map-badge')), findsOneWidget);
      expect(find.text('40 neighbors within 5 km'), findsWidgets);
      expect(find.text('Save my home and continue'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('cycle-days')),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.byKey(const ValueKey('cycle-days')), findsOneWidget);

      await tester.ensureVisible(find.byKey(const ValueKey('goal-10')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('goal-10')));
      await tester.pump();
      expect(c.dailyGoal.value, 10);
    });
  });
}
