import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:gps_cielo/core/services/address_suggestion_service.dart';
import 'package:gps_cielo/core/services/location_selection.dart';
import 'package:gps_cielo/core/services/location_service.dart';

class FakeGps extends GeolocatorPlatform {
  bool servicesEnabled = true;
  LocationPermission permission = LocationPermission.whileInUse;
  LocationPermission afterRequest = LocationPermission.whileInUse;
  Object? positionError;
  Position? lastKnown;
  int requests = 0;
  int positionCalls = 0;
  LocationSettings? lastSettings;

  @override
  Future<bool> isLocationServiceEnabled() async => servicesEnabled;

  @override
  Future<LocationPermission> checkPermission() async => permission;

  @override
  Future<LocationPermission> requestPermission() async {
    requests++;
    permission = afterRequest;
    return afterRequest;
  }

  @override
  Future<Position?> getLastKnownPosition({
    bool forceLocationManager = false,
  }) async => lastKnown;

  @override
  Future<Position> getCurrentPosition({LocationSettings? locationSettings}) {
    positionCalls++;
    lastSettings = locationSettings;
    if (positionError != null) return Future.error(positionError!);
    return Future.value(position(23.7465, 90.376, DateTime(2026)));
  }
}

Position position(double lat, double lng, DateTime at) => Position(
  latitude: lat,
  longitude: lng,
  timestamp: at,
  accuracy: 12,
  altitude: 0,
  altitudeAccuracy: 0,
  heading: 0,
  headingAccuracy: 0,
  speed: 0,
  speedAccuracy: 0,
);

class FakePhoton implements AddressSearchProvider {
  AddressSuggestion? reverseResult;
  List<AddressSuggestion> searchResults = const [];
  Object? error;
  int reverseCalls = 0;

  @override
  String get attribution => '';

  @override
  Future<AddressSuggestion?> reverse(double latitude, double longitude) async {
    reverseCalls++;
    if (error != null) throw error!;
    return reverseResult;
  }

  @override
  Future<List<AddressSuggestion>> search(
    String query, {
    double? nearLatitude,
    double? nearLongitude,
    int limit = 5,
  }) async {
    if (error != null) throw error!;
    return searchResults;
  }
}

void main() {
  late FakeGps gps;
  late FakePhoton photon;
  final now = DateTime(2026, 11, 9, 14, 0);

  LocationService build() => LocationService(
    geolocator: gps,
    addressSearch: AddressSuggestionService(
      provider: photon,
      minInterval: Duration.zero,
    ),
    clock: () => now,
  );

  setUp(() {
    gps = FakeGps();
    photon = FakePhoton();
  });

  Matcher failsWith(LocationFailure reason) => throwsA(
    isA<LocationException>().having((e) => e.reason, 'reason', reason),
  );

  group('permissions and GPS', () {
    test('disabled location services', () async {
      gps.servicesEnabled = false;
      await expectLater(
        build().currentLocation(),
        failsWith(LocationFailure.servicesDisabled),
      );
      expect(gps.requests, 0);
    });

    test('asks once when denied, then reports the denial', () async {
      gps.permission = LocationPermission.denied;
      gps.afterRequest = LocationPermission.denied;
      await expectLater(
        build().currentLocation(),
        failsWith(LocationFailure.permissionDenied),
      );
      expect(gps.requests, 1);
      expect(gps.positionCalls, 0);
    });

    test('permanently denied needs Settings and is not re-requested', () async {
      gps.permission = LocationPermission.deniedForever;
      final error = await build().currentLocation().then<Object?>(
        (_) => null,
        onError: (Object e) => e,
      );
      expect(error, isA<LocationException>());
      expect((error as LocationException).needsSettings, isTrue);
      expect(gps.requests, 0);
    });

    test(
      'granted after request uses foreground high accuracy + timeout',
      () async {
        gps.permission = LocationPermission.denied;
        gps.afterRequest = LocationPermission.whileInUse;
        final location = await build().currentLocation();
        expect(location.latitude, 23.7465);
        expect(location.source, LocationSource.gps);
        expect(gps.lastSettings?.accuracy, LocationAccuracy.high);
        expect(gps.lastSettings?.timeLimit, const Duration(seconds: 15));
      },
    );

    test('GPS timeout is reported as such', () async {
      gps.positionError = TimeoutException('no fix');
      await expectLater(
        build().currentLocation(),
        failsWith(LocationFailure.timeout),
      );
    });

    test('GPS timeout uses a recent last-known position', () async {
      gps.positionError = TimeoutException('no fix');
      gps.lastKnown = position(
        23.80,
        90.41,
        now.subtract(const Duration(minutes: 3)),
      );
      final location = await build().currentLocation();
      expect(location.latitude, 23.80);
      expect(location.source, LocationSource.gps);
    });

    test('GPS timeout ignores a stale last-known position', () async {
      gps.positionError = TimeoutException('no fix');
      gps.lastKnown = position(
        23.80,
        90.41,
        now.subtract(const Duration(hours: 2)),
      );
      await expectLater(
        build().currentLocation(),
        failsWith(LocationFailure.timeout),
      );
    });

    test('other GPS errors become "unavailable"', () async {
      gps.positionError = StateError('boom');
      await expectLater(
        build().currentLocation(),
        failsWith(LocationFailure.unavailable),
      );
    });
  });

  group('reverse geocoding', () {
    test(
      'looks the address up with Photon, keeping the GPS coordinates',
      () async {
        photon.reverseResult = const AddressSuggestion(
          title: 'Dhanmondi 9A',
          subtitle: 'Dhanmondi, Dhaka, Bangladesh',
          latitude: 23.74,
          longitude: 90.37,
        );
        final location = await build().currentLocation();
        expect(location.address, 'Dhanmondi 9A, Dhanmondi, Dhaka, Bangladesh');
        // The GPS coordinates are kept, not the address feature's.
        expect(location.latitude, 23.7465);
        expect(location.longitude, 90.376);
        expect(photon.reverseCalls, 1);
      },
    );

    test(
      'keeps coordinates with an empty address when nothing is found',
      () async {
        photon.error = const AddressSearchException('offline');
        final location = await build().currentLocation();
        expect(location.hasAddress, isFalse);
        expect(location.address, isEmpty);
        expect(location.coordinatesLabel, '23.74650, 90.37600');
      },
    );
  });

  group('forward geocoding', () {
    test('Photon, then a clear error', () async {
      photon.searchResults = const [
        AddressSuggestion(
          title: 'Mirpur',
          subtitle: 'Dhaka',
          latitude: 23.82,
          longitude: 90.36,
        ),
      ];
      final viaPhoton = await build().resolveAddress('Mirpur 10');
      expect(viaPhoton.latitude, 23.82);
      expect(viaPhoton.address, 'Mirpur 10');

      photon.searchResults = const [];
      await expectLater(
        build().resolveAddress('Nowhere 123'),
        throwsA(isNot(isA<LocationException>())),
      );
    });
  });

  group('LocationSelection', () {
    const picked = ResolvedLocation(
      address: 'Dhanmondi, Dhaka, Bangladesh',
      latitude: 23.74,
      longitude: 90.37,
      source: LocationSource.search,
    );

    test('a suggestion applies only while the text is unchanged', () {
      final selection = LocationSelection()..pick(picked);
      expect(selection.locationFor('Dhanmondi, Dhaka, Bangladesh'), picked);
      expect(selection.locationFor('Gulshan, Dhaka'), isNull);
    });

    test('GPS without an address uses the typed text as its label', () {
      final selection = LocationSelection()
        ..pick(
          const ResolvedLocation(
            address: '',
            latitude: 23.7,
            longitude: 90.3,
            source: LocationSource.gps,
          ),
        );
      expect(selection.appliesTo(''), isTrue);
      final saved = selection.locationFor('House 12, Road 3');
      expect(saved?.address, 'House 12, Road 3');
      expect(saved?.latitude, 23.7);
      expect(selection.locationFor('   '), isNull);
    });

    test('GPS with an address is re-geocoded when the text changes', () {
      final selection = LocationSelection()
        ..pick(
          const ResolvedLocation(
            address: 'Road 7, Dhaka',
            latitude: 23.7,
            longitude: 90.3,
            source: LocationSource.gps,
          ),
        );
      expect(selection.locationFor('Road 7, Dhaka')?.latitude, 23.7);
      expect(selection.locationFor('Uttara Sector 4'), isNull);
    });
  });
}
