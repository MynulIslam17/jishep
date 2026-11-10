import 'dart:async';

import 'package:geolocator/geolocator.dart';
import 'package:gps_cielo/core/services/address_suggestion_service.dart';
import 'package:gps_cielo/core/utils/firebase_error_mapper.dart';

/// Where a location came from.
enum LocationSource {
  /// Picked from the address suggestions.
  search,

  /// The device's GPS position.
  gps,

  /// Geocoded from text the user typed.
  manual,
}

class ResolvedLocation {
  /// Human-readable address. Empty when GPS found a position but no mapped
  /// address exists there; the coordinates are still valid.
  final String address;
  final double latitude;
  final double longitude;
  final LocationSource source;

  const ResolvedLocation({
    required this.address,
    required this.latitude,
    required this.longitude,
    this.source = LocationSource.manual,
  });

  bool get hasAddress => address.trim().isNotEmpty;

  String get coordinatesLabel =>
      '${latitude.toStringAsFixed(5)}, ${longitude.toStringAsFixed(5)}';

  ResolvedLocation withAddress(String newAddress) => ResolvedLocation(
    address: newAddress,
    latitude: latitude,
    longitude: longitude,
    source: source,
  );
}

enum LocationFailure {
  servicesDisabled,
  permissionDenied,
  permissionDeniedForever,
  timeout,
  unavailable,
}

class LocationException extends AppException {
  final LocationFailure reason;

  const LocationException(this.reason, super.message);

  /// The user must change a system setting before retrying.
  bool get needsSettings =>
      reason == LocationFailure.servicesDisabled ||
      reason == LocationFailure.permissionDeniedForever;
}

/// Device GPS (foreground, one-shot) and address <-> coordinate conversion.
///
/// Addresses are looked up with Photon (OpenStreetMap) over HTTP from Dart.
/// The Android platform `Geocoder` is deliberately not used: the geocoding
/// plugin calls it from the app's main thread, which froze the app (ANR)
/// whenever the system geocoder was slow. Only coordinates are sent to Photon.
///
/// Nothing here tracks the user continuously or in the background.
class LocationService {
  LocationService({
    GeolocatorPlatform? geolocator,
    AddressSuggestionService? addressSearch,
    this.gpsTimeout = const Duration(seconds: 15),
    this.addressTimeout = const Duration(seconds: 10),
    this.maxLastKnownAge = const Duration(minutes: 10),
    DateTime Function()? clock,
  }) : _geolocator = geolocator,
       _addressSearch = addressSearch,
       _now = clock ?? DateTime.now;

  final GeolocatorPlatform? _geolocator;
  final AddressSuggestionService? _addressSearch;
  final DateTime Function() _now;

  /// How long to wait for a fresh GPS fix.
  final Duration gpsTimeout;

  /// How long to wait for an address before continuing without one.
  final Duration addressTimeout;

  /// A last-known position younger than this is used when no fresh fix
  /// arrives in time.
  final Duration maxLastKnownAge;

  GeolocatorPlatform get _gps => _geolocator ?? GeolocatorPlatform.instance;

  /// Asks for permission if needed, reads the GPS position once and looks up
  /// the nearest address. The address is empty when none could be found.
  /// Throws [LocationException].
  Future<ResolvedLocation> currentLocation() async {
    final position = await currentPosition();
    final address = await addressFromCoordinates(
      position.latitude,
      position.longitude,
    );
    return ResolvedLocation(
      address: address ?? '',
      latitude: position.latitude,
      longitude: position.longitude,
      source: LocationSource.gps,
    );
  }

  /// Reads the device position once. Throws [LocationException].
  Future<Position> currentPosition() async {
    if (!await _gps.isLocationServiceEnabled()) {
      throw const LocationException(
        LocationFailure.servicesDisabled,
        'Location services are turned off. Turn them on or type your address.',
      );
    }

    var permission = await _gps.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await _gps.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) {
      throw const LocationException(
        LocationFailure.permissionDeniedForever,
        'Location permission is blocked. Enable it in Settings or type your address.',
      );
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.unableToDetermine) {
      throw const LocationException(
        LocationFailure.permissionDenied,
        'Location permission was denied. You can type your address instead.',
      );
    }

    try {
      return await _gps
          .getCurrentPosition(
            locationSettings: LocationSettings(
              accuracy: LocationAccuracy.high,
              timeLimit: gpsTimeout,
            ),
          )
          // Safety net in case the platform never answers.
          .timeout(gpsTimeout + const Duration(seconds: 5));
    } on TimeoutException {
      final recent = await _recentLastKnownPosition();
      if (recent != null) return recent;
      throw const LocationException(
        LocationFailure.timeout,
        'Could not get a GPS fix in time. Try again or type your address.',
      );
    } on LocationServiceDisabledException {
      throw const LocationException(
        LocationFailure.servicesDisabled,
        'Location services are turned off. Turn them on or type your address.',
      );
    } on PermissionDeniedException {
      throw const LocationException(
        LocationFailure.permissionDenied,
        'Location permission was denied. You can type your address instead.',
      );
    } catch (_) {
      throw const LocationException(
        LocationFailure.unavailable,
        'Your location is unavailable right now. Try again or type your address.',
      );
    }
  }

  Future<Position?> _recentLastKnownPosition() async {
    try {
      final last = await _gps.getLastKnownPosition().timeout(
        const Duration(seconds: 3),
      );
      if (last == null) return null;
      final age = _now().difference(last.timestamp);
      return age <= maxLastKnownAge ? last : null;
    } catch (_) {
      return null;
    }
  }

  /// Opens the system screen that fixes [failure].
  Future<bool> openSettingsFor(LocationFailure failure) {
    return failure == LocationFailure.servicesDisabled
        ? _gps.openLocationSettings()
        : _gps.openAppSettings();
  }

  /// Geocodes a free-form address into coordinates.
  Future<ResolvedLocation> resolveAddress(String address) async {
    final trimmed = address.trim();
    if (trimmed.isEmpty) {
      throw const AppException('Please enter an address.');
    }

    final search = _addressSearch;
    if (search != null) {
      try {
        final results = await search
            .search(trimmed, limit: 1)
            .timeout(addressTimeout);
        if (results.isNotEmpty) {
          return ResolvedLocation(
            address: trimmed,
            latitude: results.first.latitude,
            longitude: results.first.longitude,
          );
        }
      } on AddressSearchException {
        // Reported below as not found.
      } on TimeoutException {
        // Reported below as not found.
      }
    }

    throw const AppException(
      'We could not find that address. Pick a suggestion or add the city.',
    );
  }

  /// Nearest readable address for a point, or null when none is known.
  /// Never returns raw coordinates as an address.
  Future<String?> addressFromCoordinates(
    double latitude,
    double longitude,
  ) async {
    final search = _addressSearch;
    if (search == null) return null;
    try {
      final place = await search
          .reverse(latitude, longitude)
          .timeout(addressTimeout);
      final address = place?.fullAddress.trim();
      return address == null || address.isEmpty ? null : address;
    } catch (_) {
      // Offline, rate limited or slow: continue with coordinates only.
      return null;
    }
  }
}
