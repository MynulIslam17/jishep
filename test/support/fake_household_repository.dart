import 'dart:async';

import 'package:gps_cielo/core/data/geo_search.dart';
import 'package:gps_cielo/core/data/household_repository.dart';
import 'package:gps_cielo/core/models/household_model.dart';
import 'package:gps_cielo/features/notifications/data/repositories/notification_repository.dart';

import 'synthetic_households.dart';

class FakeHouseholdRepository implements HouseholdRepository {
  /// Every search started (center and range).
  final List<({double latitude, double longitude, double radiusKm})> fetches =
      [];
  final List<({String uid, String householdId})> savedStatuses = [];
  final statusStreams =
      <String, StreamController<Map<String, Map<String, dynamic>>>>{};

  /// Statuses on the "server", by user and household.
  final serverStatuses = <String, Map<String, Map<String, dynamic>>>{};

  /// Household ids whose status was read with [fetchStatuses].
  final statusReads = <String>[];

  /// Firestore reads of the most recent search.
  IndexedHouseholds? lastIndex;

  @override
  GeoSearch geoSearch({
    required double latitude,
    required double longitude,
    required double radiusKm,
  }) {
    fetches.add((latitude: latitude, longitude: longitude, radiusKm: radiusKm));
    // Homes going north from the center, ~100 m (0.000899°) apart.
    final index = IndexedHouseholds([
      for (var i = 0; i < available; i++)
        (id: 'demo_$i', lat: latitude + 0.0008990 * (i + 1), lng: longitude),
    ], fields: (h) => {'residentName': 'Demo ${h.id}'});
    lastIndex = index;
    return GeoSearch(
      query: index.query,
      latitude: latitude,
      longitude: longitude,
      maxMeters: radiusKm * 1000,
    );
  }

  /// How many households exist near any point (0 = none).
  int available = 0;

  @override
  Future<Map<String, Map<String, dynamic>>> fetchStatuses(
    String uid,
    Iterable<String> ids,
  ) async {
    final all = serverStatuses[uid] ?? const {};
    final out = <String, Map<String, dynamic>>{};
    for (final id in ids) {
      statusReads.add(id);
      final status = all[id];
      if (status != null) out[id] = status;
    }
    return out;
  }

  @override
  Stream<Map<String, Map<String, dynamic>>> watchStatusChanges(
    String uid, {
    required DateTime since,
  }) {
    return (statusStreams[uid] ??= StreamController.broadcast()).stream;
  }

  @override
  Future<Map<String, int>> countStatuses(String uid) async {
    final all = (serverStatuses[uid] ?? const {}).values;
    int count(String f) => all.where((s) => s[f] == true).length;
    return {
      'all': all.length,
      for (final f in const [
        'isPrayed',
        'isVisited',
        'isInvited',
        'hasFollowUp',
      ])
        f: count(f),
    };
  }

  @override
  Future<void> saveStatus({
    required String uid,
    required HouseholdModel household,
    required bool wasPrayed,
  }) async {
    savedStatuses.add((uid: uid, householdId: household.id));
    final error = failWith;
    if (error != null) throw error;
  }

  /// When set, every status write fails with this error.
  Object? failWith;

  /// A status change arriving from the server (another device, or the
  /// echo of a local write).
  void emitStatuses(String uid, Map<String, Map<String, dynamic>> statuses) {
    (serverStatuses[uid] ??= {}).addAll(statuses);
    statusStreams[uid]!.add(statuses);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeNotificationRepository implements NotificationRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
