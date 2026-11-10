import 'dart:math' as math;

/// Minimal geohash helpers (the same encoding the household documents use in
/// `geo.geohash`, written by `tool/seed_households`).
abstract final class Geohash {
  static const String alphabet = '0123456789bcdefghjkmnpqrstuvwxyz';

  /// Longest prefix searched; ~5 m cells.
  static const int maxPrecision = 9;

  static String encode(double latitude, double longitude, int precision) {
    var minLat = -90.0, maxLat = 90.0;
    var minLng = -180.0, maxLng = 180.0;
    final out = StringBuffer();
    var bit = 0, ch = 0;
    var evenBit = true;
    while (out.length < precision) {
      if (evenBit) {
        final mid = (minLng + maxLng) / 2;
        if (longitude >= mid) {
          ch = (ch << 1) | 1;
          minLng = mid;
        } else {
          ch = ch << 1;
          maxLng = mid;
        }
      } else {
        final mid = (minLat + maxLat) / 2;
        if (latitude >= mid) {
          ch = (ch << 1) | 1;
          minLat = mid;
        } else {
          ch = ch << 1;
          maxLat = mid;
        }
      }
      evenBit = !evenBit;
      if (++bit == 5) {
        out.write(alphabet[ch]);
        bit = 0;
        ch = 0;
      }
    }
    return out.toString();
  }

  /// The latitude/longitude box a geohash covers.
  static GeoBox bounds(String hash) {
    var minLat = -90.0, maxLat = 90.0;
    var minLng = -180.0, maxLng = 180.0;
    var evenBit = true;
    for (final c in hash.split('')) {
      final value = alphabet.indexOf(c);
      if (value < 0) throw ArgumentError.value(hash, 'hash');
      for (var n = 4; n >= 0; n--) {
        final bitOn = (value >> n) & 1 == 1;
        if (evenBit) {
          final mid = (minLng + maxLng) / 2;
          bitOn ? minLng = mid : maxLng = mid;
        } else {
          final mid = (minLat + maxLat) / 2;
          bitOn ? minLat = mid : maxLat = mid;
        }
        evenBit = !evenBit;
      }
    }
    return GeoBox(minLat, minLng, maxLat, maxLng);
  }

  /// The 32 cells one level finer.
  static List<String> children(String hash) => [
    for (final c in alphabet.split('')) '$hash$c',
  ];

  /// Approximate cell height and width in meters at [latitude].
  static ({double height, double width}) cellSize(
    int precision,
    double latitude,
  ) {
    final lngBits = (precision * 5 / 2).ceil();
    final latBits = (precision * 5 / 2).floor();
    final heightDeg = 180 / math.pow(2, latBits);
    final widthDeg = 360 / math.pow(2, lngBits);
    const metersPerDeg = 111320.0;
    return (
      height: heightDeg * metersPerDeg,
      width: widthDeg * metersPerDeg * math.cos(latitude * math.pi / 180),
    );
  }
}

class GeoBox {
  const GeoBox(this.minLat, this.minLng, this.maxLat, this.maxLng);

  final double minLat;
  final double minLng;
  final double maxLat;
  final double maxLng;

  /// Shortest distance in meters from (lat, lng) to this box (0 inside).
  double distanceMetersFrom(double lat, double lng) {
    final nearestLat = lat.clamp(minLat, maxLat).toDouble();
    final nearestLng = lng.clamp(minLng, maxLng).toDouble();
    return haversineMeters(lat, lng, nearestLat, nearestLng);
  }
}

/// Great-circle distance in meters.
double haversineMeters(double lat1, double lng1, double lat2, double lng2) {
  const r = 6371008.8;
  final dLat = (lat2 - lat1) * math.pi / 180;
  final dLng = (lng2 - lng1) * math.pi / 180;
  final a =
      math.pow(math.sin(dLat / 2), 2) +
      math.cos(lat1 * math.pi / 180) *
          math.cos(lat2 * math.pi / 180) *
          math.pow(math.sin(dLng / 2), 2);
  return 2 * r * math.asin(math.min(1, math.sqrt(a)));
}
