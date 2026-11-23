import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gps_cielo/core/data/geo_record.dart';

/// The homes of one prayer round (`users/{uid}/prayer_rounds/{roundId}`),
/// fixed when the round is first shown, so a changed cache answer or a
/// search elsewhere never changes the list in the middle of a round.
///
/// Members keep only what is needed to show the home again (id, point,
/// street, city): never owner names, which reach the app only through the
/// server.
class PrayerRound {
  const PrayerRound({
    required this.members,
    this.centerLatitude,
    this.centerLongitude,
    this.target,
  });

  /// The round's homes, nearest first as when the round was fixed.
  final List<GeoRecord> members;

  /// The saved home the members were chosen around.
  final double? centerLatitude;
  final double? centerLongitude;

  /// The Settings count ("households to show") the round was fixed with.
  final int? target;

  bool get hasMembers => members.isNotEmpty;

  List<String> get ids => [for (final m in members) m.id];

  bool contains(String id) => members.any((m) => m.id == id);

  /// Reads a round document; null when it has no member list (rounds
  /// written before members were recorded hold only `householdIds`).
  static PrayerRound? fromFirestore(Map<String, dynamic>? data) {
    final raw = data?['members'];
    if (raw is! List) return null;
    final members = <GeoRecord>[];
    for (final m in raw) {
      if (m is! Map) continue;
      final id = m['i'];
      final lat = m['a'];
      final lon = m['o'];
      if (id is! String || lat is! num || lon is! num) continue;
      members.add(
        GeoRecord(
          id: id,
          latitude: lat.toDouble(),
          longitude: lon.toDouble(),
          geohash: '',
          address: m['l']?.toString() ?? '',
          cityStateZip: m['c']?.toString() ?? '',
        ),
      );
    }
    if (members.isEmpty) return null;
    final center = data?['center'];
    final target = data?['target'];
    return PrayerRound(
      members: members,
      centerLatitude: center is GeoPoint ? center.latitude : null,
      centerLongitude: center is GeoPoint ? center.longitude : null,
      target: target is num ? target.toInt() : null,
    );
  }

  /// The membership fields of the round document (at most 200 homes).
  Map<String, dynamic> toFirestore() {
    final list = members.take(200).toList();
    return {
      'members': [
        for (final m in list)
          {
            'i': m.id,
            'a': m.latitude,
            'o': m.longitude,
            'l': m.address,
            if (m.cityStateZip.isNotEmpty) 'c': m.cityStateZip,
          },
      ],
      'householdIds': [for (final m in list) m.id],
      'size': list.length,
      if (target != null) 'target': target,
      if (centerLatitude != null && centerLongitude != null)
        'center': GeoPoint(centerLatitude!, centerLongitude!),
    };
  }
}
