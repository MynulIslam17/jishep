import 'package:geocoding/geocoding.dart' as geo;
import 'package:geolocator/geolocator.dart';
import 'package:gps_cielo/core/utils/api_debug_log.dart';
import 'package:gps_cielo/core/utils/firebase_error_mapper.dart';

class ResolvedLocation {
  final String address;
  final double latitude;
  final double longitude;

  const ResolvedLocation({
    required this.address,
    required this.latitude,
    required this.longitude,
  });
}

/// Device GPS and address <-> coordinate conversion.
class LocationService {
  geo.Geocoding? _geocoding;

  geo.Geocoding get _geocoder => _geocoding ??= geo.Geocoding();

  /// Reads the device position and resolves it to a street address.
  Future<ResolvedLocation> currentLocation() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const AppException('Location services are turned off.');
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied) {
      throw const AppException('Location permission was denied.');
    }
    if (permission == LocationPermission.deniedForever) {
      throw const AppException(
        'Location permission is blocked. Enable it in Settings.',
      );
    }

    final position = await ApiDebugLog.run(
      'LocationService.getCurrentPosition',
      () => Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 20),
        ),
      ),
    );

    final address = await addressFromCoordinates(
      position.latitude,
      position.longitude,
    );

    return ResolvedLocation(
      address: address,
      latitude: position.latitude,
      longitude: position.longitude,
    );
  }

  /// Geocodes a free-form address into coordinates.
  Future<ResolvedLocation> resolveAddress(String address) async {
    final trimmed = address.trim();
    try {
      final results = await ApiDebugLog.run(
        'LocationService.resolveAddress',
        () => _geocoder.locationFromAddress(trimmed),
        details: trimmed,
      );
      if (results.isEmpty) {
        throw const AppException('We could not find that address.');
      }
      return ResolvedLocation(
        address: trimmed,
        latitude: results.first.latitude,
        longitude: results.first.longitude,
      );
    } on AppException {
      rethrow;
    } catch (_) {
      throw const AppException(
        'We could not find that address. Try adding city and ZIP code.',
      );
    }
  }

  Future<String> addressFromCoordinates(double latitude, double longitude) async {
    try {
      final placemarks = await ApiDebugLog.run(
        'LocationService.addressFromCoordinates',
        () => _geocoder.placemarkFromCoordinates(latitude, longitude),
        details: '$latitude,$longitude',
      );
      if (placemarks.isEmpty) return _formatCoordinates(latitude, longitude);

      final p = placemarks.first;
      final street = [p.subThoroughfare, p.thoroughfare]
          .where((part) => part != null && part.isNotEmpty)
          .join(' ');
      final region = [p.administrativeArea, p.postalCode]
          .where((part) => part != null && part.isNotEmpty)
          .join(' ');
      final parts = [
        street.isNotEmpty ? street : p.name,
        p.locality,
        region,
      ].where((part) => part != null && part.isNotEmpty);

      final formatted = parts.join(', ');
      return formatted.isNotEmpty
          ? formatted
          : _formatCoordinates(latitude, longitude);
    } catch (_) {
      return _formatCoordinates(latitude, longitude);
    }
  }

  String _formatCoordinates(double latitude, double longitude) {
    return '${latitude.toStringAsFixed(5)}, ${longitude.toStringAsFixed(5)}';
  }
}
