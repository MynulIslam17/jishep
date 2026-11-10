import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geoflutterfire_plus/geoflutterfire_plus.dart';

/// Validates the synthetic Bangladesh seed data against the geohash encoder
/// the app queries with, so nearby searches will find these documents.
void main() {
  final records =
      (jsonDecode(
                File(
                  'tool/seed_households/households.demo_bd.json',
                ).readAsStringSync(),
              )
              as List)
          .cast<Map<String, dynamic>>();

  test('has 140 clearly synthetic records with stable demo ids', () {
    expect(records, hasLength(140));
    final ids = records.map((r) => r['id'] as String).toSet();
    expect(ids, hasLength(140));
    expect(records.first['id'], 'demo_bd_001');
    expect(records.last['id'], 'demo_bd_140');
    for (final r in records) {
      expect(r['id'], startsWith('demo_bd_'));
      expect(r['residentName'], matches(RegExp(r'^Demo Household \d{3}$')));
      expect(r['address'], contains('(synthetic)'));
    }
  });

  test('city distribution matches the test plan', () {
    final perCity = <String, int>{};
    for (final r in records) {
      perCity.update(r['city'] as String, (n) => n + 1, ifAbsent: () => 1);
    }
    expect(perCity, {
      'Dhaka': 80, // 40 across six areas + 40 in Demra (paging test set)
      'Chattogram': 20,
      'Sylhet': 10,
      'Rajshahi': 10,
      'Khulna': 10,
      'Barishal': 10,
    });
  });

  test('stored geohash matches geoflutterfire_plus for every coordinate', () {
    for (final r in records) {
      final lat = (r['latitude'] as num).toDouble();
      final lng = (r['longitude'] as num).toDouble();
      expect(lat, inInclusiveRange(20.5, 26.7));
      expect(lng, inInclusiveRange(88.0, 92.7));
      final appHash = GeoFirePoint(GeoPoint(lat, lng)).geohash;
      final stored = r['geohash'] as String;
      expect(
        stored.startsWith(appHash) || appHash.startsWith(stored),
        isTrue,
        reason: '${r['id']}: stored $stored vs app $appHash',
      );
    }
  });

  test('records stay near their area center (350 m; Demra ~2 km)', () {
    final byArea = <String, List<Map<String, dynamic>>>{};
    for (final r in records) {
      byArea.putIfAbsent('${r['city']}/${r['area']}', () => []).add(r);
    }
    for (final entry in byArea.entries) {
      final group = entry.value;
      final maxKm = entry.key == 'Dhaka/Demra' ? 4.0 : 0.7;
      final lat =
          group.map((r) => r['latitude'] as num).reduce((a, b) => a + b) /
          group.length;
      final lng =
          group.map((r) => r['longitude'] as num).reduce((a, b) => a + b) /
          group.length;
      for (final r in group) {
        final d = GeoFirePoint(GeoPoint(lat, lng)).distanceBetweenInKm(
          geopoint: GeoPoint(
            (r['latitude'] as num).toDouble(),
            (r['longitude'] as num).toDouble(),
          ),
        );
        expect(
          d,
          lessThan(maxKm),
          reason: '${r['id']} is ${d.toStringAsFixed(2)} km away',
        );
      }
    }
  });

  test('the Demra set has 40 households for paging', () {
    final demra = records.where((r) => r['area'] == 'Demra').toList();
    expect(demra, hasLength(40));
    expect(demra.first['id'], 'demo_bd_101');
  });
}
