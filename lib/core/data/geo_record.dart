import 'package:cloud_firestore/cloud_firestore.dart';

/// One household location, whatever it was read from: a `households/{id}`
/// document or an Overture cell (`cells/{prefix}`).
class GeoRecord {
  const GeoRecord({
    required this.id,
    required this.latitude,
    required this.longitude,
    required this.geohash,
    required this.address,
    this.cityStateZip = '',
  });

  final String id;
  final double latitude;
  final double longitude;

  /// 9-character geohash of the point.
  final String geohash;

  /// Street address, e.g. "3510 HELIX ST" or "3173 BANCROFT DR APT 01".
  final String address;

  /// e.g. "SPRING VALLEY, CA 91977" (may be empty).
  final String cityStateZip;

  /// A `households/{id}` document (`geo.geopoint`, `geo.geohash`, `address`,
  /// `cityStateZip`). Its `residentName` is a placeholder and is ignored:
  /// names are the user's own, in `household_status`.
  factory GeoRecord.fromSnapshot(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    final geo = data['geo'];
    final point = geo is Map ? geo['geopoint'] : null;
    final hash = geo is Map ? geo['geohash'] : null;
    return GeoRecord(
      id: doc.id,
      latitude: point is GeoPoint ? point.latitude : 0,
      longitude: point is GeoPoint ? point.longitude : 0,
      geohash: hash is String ? hash : '',
      address: data['address']?.toString() ?? '',
      cityStateZip: data['cityStateZip']?.toString() ?? '',
    );
  }

  /// One entry of a cell file: `{i, a, o, g, l, c?, z?}` (see
  /// tool/overture_cells/build_cells.py).
  factory GeoRecord.fromCell(Map<String, dynamic> h) {
    final city = h['c'] as String?;
    final zip = h['z'] as String?;
    return GeoRecord(
      id: h['i'] as String,
      latitude: (h['a'] as num).toDouble(),
      longitude: (h['o'] as num).toDouble(),
      geohash: h['g'] as String? ?? '',
      address: h['l'] as String? ?? '',
      cityStateZip: [
        if (city != null && city.isNotEmpty) city,
        if (zip != null && zip.isNotEmpty) zip,
      ].join(' '),
    );
  }
}
