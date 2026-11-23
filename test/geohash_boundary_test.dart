import 'package:flutter_test/flutter_test.dart';
import 'package:gps_cielo/core/utils/geohash.dart';

void main() {
  // Expected values from geofire-common's geohashForLocation([lat, lng], 9)
  // (the encoder tool/overture_cells and tool/seed_households match).
  // Points exactly on a cell boundary go to the lower cell ("7zzz…" for
  // 0,0 — a `>=` rule would give "s000…").
  const vectors = [
    (0.0, 0.0, '7zzzzzzzz'),
    (0.0, -180.0, '2pbpbpbpb'),
    (-90.0, 0.0, '5bpbpbpbp'),
    (45.0, 90.0, 'tzzzzzzzz'),
    (-45.0, -90.0, '1zzzzzzzz'),
    (22.5, 11.25, 's5zzzzzzz'),
    (32.7268967, -116.9635121, '9muf4mtzb'),
    (40.7357, -74.1724, 'dr5r8ptq9'),
    (23.7104, 90.4074, 'wh0qck2ej'),
    (32.72, -117.02, '9muf1hkxu'),
  ];

  test('Geohash.encode matches geofire-common, including boundaries', () {
    for (final (lat, lng, expected) in vectors) {
      expect(Geohash.encode(lat, lng, 9), expected, reason: '($lat, $lng)');
    }
  });

  test('a point is inside the bounds of its own cell', () {
    for (final (lat, lng, _) in vectors) {
      for (var p = 1; p <= 9; p++) {
        final box = Geohash.bounds(Geohash.encode(lat, lng, p));
        expect(box.distanceMetersFrom(lat, lng), 0, reason: '($lat, $lng) p$p');
      }
    }
  });
}
