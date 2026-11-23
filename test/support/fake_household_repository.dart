import 'package:gps_cielo/core/data/gap_fill.dart';
import 'package:gps_cielo/core/data/area_search.dart';
import 'package:gps_cielo/core/config/feature_flags.dart';
import 'dart:async';

import 'package:gps_cielo/core/data/cell_source.dart';
import 'package:gps_cielo/core/data/geo_search.dart';
import 'package:gps_cielo/core/data/household_repository.dart';
import 'package:gps_cielo/core/models/household_model.dart';
import 'package:gps_cielo/core/models/prayer_round.dart';
import 'package:gps_cielo/features/notifications/data/repositories/notification_repository.dart';

import 'synthetic_households.dart';

class FakeHouseholdRepository implements HouseholdRepository {
  /// Every search started (center and range).
  final List<({double latitude, double longitude, double radiusKm})> fetches =
      [];
  final List<({String uid, String householdId})> savedStatuses = [];

  /// Resident names written (null = removed), in order.
  final List<({String id, String? name})> savedNames = [];
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
        (
          id: '$idPrefix$i',
          lat: latitude + 0.0008990 * (i + 1),
          lng: longitude,
        ),
    ], fields: (h) => {'residentName': 'Demo ${h.id}'});
    lastIndex = index;
    return GeoSearch(
      query: index.query,
      latitude: latitude,
      longitude: longitude,
      maxMeters: radiusKm * 1000,
    );
  }

  /// Household id prefix (a changed answer for the same place).
  String idPrefix = 'demo_';

  /// How many households exist near any point (0 = none).
  int available = 0;

  /// Overture cells, for tests with `FeatureFlags.useCellHouseholds` on.
  FirestoreCellSource? cells;

  /// Cell areas started (center).
  final List<({double latitude, double longitude})> cellFetches = [];

  @override
  CellArea cellArea({required double latitude, required double longitude}) {
    cellFetches.add((latitude: latitude, longitude: longitude));
    return cells!.area(latitude: latitude, longitude: longitude);
  }

  @override
  GapFillService gapFillService = GapFillService(call: (_) async => {});

  /// Every nearestArea request (preview = location setup).
  final nearestAreaCalls =
      <({double latitude, double longitude, bool preview})>[];

  @override
  AreaSearch nearestArea({
    required double latitude,
    required double longitude,
    bool preview = false,
  }) {
    nearestAreaCalls.add((
      latitude: latitude,
      longitude: longitude,
      preview: preview,
    ));
    final cells = cellArea(latitude: latitude, longitude: longitude);
    if (preview || !FeatureFlags.melissaGapFill) return cells;
    return GapFilledArea(
      inner: cells,
      service: gapFillService,
      latitude: latitude,
      longitude: longitude,
    );
  }

  /// Owner names returned by [fetchOwnerNames], by uid.
  final Map<String, Map<String, String>> ownerNames = {};

  @override
  Future<Map<String, String>> fetchOwnerNames(String uid) async =>
      ownerNames[uid] ?? const {};

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
    bool nameChanged = false,
    String? roundId,
  }) async {
    savedStatuses.add((uid: uid, householdId: household.id));
    savedRounds.add(roundId);
    if (nameChanged) {
      savedNames.add((id: household.id, name: household.residentName));
    }
    final error = failWith;
    if (error != null) throw error;
  }

  /// Prayer rounds on the "server", by user and round id.
  final rounds = <String, Map<String, PrayerRound>>{};

  /// Every round membership written (uid, round id, homes).
  final roundWrites = <({String uid, String roundId, List<String> ids})>[];

  /// When set, reading rounds fails (e.g. rules without prayer_rounds).
  Object? roundReadError;

  /// Lifetime prayer events on the "server", by user.
  final prayerEvents = <String, int>{};

  @override
  Future<PrayerRound?> fetchRound(String uid, String roundId) async {
    final error = roundReadError;
    if (error != null) throw error;
    return rounds[uid]?[roundId];
  }

  @override
  Future<void> saveRoundMembers(
    String uid,
    String roundId,
    PrayerRound round,
  ) async {
    roundWrites.add((uid: uid, roundId: roundId, ids: round.ids));
    (rounds[uid] ??= {})[roundId] = round;
  }

  @override
  Future<int> countPrayerEvents(String uid) async => prayerEvents[uid] ?? 0;

  /// The round id passed with each status write.
  final savedRounds = <String?>[];

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
