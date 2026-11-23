import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gps_cielo/core/config/feature_flags.dart';
import 'package:gps_cielo/core/data/area_search.dart';
import 'package:gps_cielo/core/data/cell_source.dart';
import 'package:gps_cielo/core/data/gap_fill.dart';
import 'package:gps_cielo/core/data/geo_search.dart';
import 'package:gps_cielo/core/data/owner_discovery.dart';
import 'package:gps_cielo/core/constants/firestore_paths.dart';
import 'package:gps_cielo/core/models/household_model.dart';
import 'package:gps_cielo/core/models/prayer_round.dart';

typedef HouseholdSnapshot = DocumentSnapshot<Map<String, dynamic>>;

/// One page of the user's status documents, newest first.
class StatusPage {
  const StatusPage({required this.docs, required this.hasMore, this.cursor});

  final List<HouseholdSnapshot> docs;

  /// True when more documents exist after this page.
  final bool hasMore;

  /// Pass to the next [HouseholdRepository.fetchStatusPage] call.
  final HouseholdSnapshot? cursor;
}

/// Firestore access for the shared household directory and the signed-in
/// user's per-household status documents.
class HouseholdRepository {
  final FirebaseFirestore _db;

  HouseholdRepository({
    FirebaseFirestore? firestore,
    FirestoreCellSource? cellSource,
  }) : _db = firestore ?? FirebaseFirestore.instance,
       _cellSource = cellSource;

  FirestoreCellSource? _cellSource;

  /// Overture cells (`cells/{prefix}`), created on first use.
  FirestoreCellSource get cellSource => _cellSource ??= FirestoreCellSource(
    reader: FirestoreCellReader(firestore: _db),
  );

  /// The nearest households around a point from the Overture cells
  /// (used when `FeatureFlags.useCellHouseholds` is on).
  CellArea cellArea({required double latitude, required double longitude}) =>
      cellSource.area(latitude: latitude, longitude: longitude);

  /// The nearest 50 homes around a point.
  ///
  /// - Overture cells, topped up with Melissa addresses when
  ///   `FeatureFlags.melissaGapFill` is on and Overture has fewer than 50;
  /// - with `FeatureFlags.melissaOwners` (default on), each home that has a
  ///   stored owner record at the same address shows its recorded owner
  ///   ([OwnerOverlayArea]); other homes keep their address.
  ///
  /// [preview] (location setup, pin dragging): Overture only, never the
  /// Melissa-first lookup, so trying out spots can never cost credits.
  AreaSearch nearestArea({
    required double latitude,
    required double longitude,
    bool preview = false,
  }) {
    final cells = cellArea(latitude: latitude, longitude: longitude);
    final AreaSearch overture = FeatureFlags.melissaGapFill && !preview
        ? GapFilledArea(
            inner: cells,
            service: gapFillService,
            latitude: latitude,
            longitude: longitude,
          )
        : cells;
    if (!FeatureFlags.melissaOwners || preview) return overture;
    return OwnerOverlayArea(
      inner: overture,
      owners: OwnerArea(
        service: ownerService,
        latitude: latitude,
        longitude: longitude,
      ),
    );
  }

  /// The Melissa-first owner discovery client; replaced in tests.
  OwnerDiscoveryService ownerService = OwnerDiscoveryService();

  /// The gap-filler client; replaced in tests.
  GapFillService gapFillService = GapFillService();

  CollectionReference<Map<String, dynamic>> get _households =>
      _db.collection(FirestorePaths.households);

  /// Households whose geohash starts with [prefix], in geohash order (one
  /// cell of a [GeoSearch]).
  Future<List<HouseholdSnapshot>> fetchCell(
    String prefix, {
    required int limit,
    HouseholdSnapshot? startAfter,
  }) async {
    Query<Map<String, dynamic>> query = _households.orderBy('geo.geohash');
    query = startAfter == null
        ? query.startAt([prefix])
        : query.startAfterDocument(startAfter);
    final snapshot = await query.endAt(['$prefix~']).limit(limit).get();
    return snapshot.docs;
  }

  /// A nearest-first search around a point, read progressively.
  GeoSearch geoSearch({
    required double latitude,
    required double longitude,
    required double radiusKm,
  }) {
    return GeoSearch(
      query: fetchCell,
      latitude: latitude,
      longitude: longitude,
      maxMeters: radiusKm * 1000,
    );
  }

  CollectionReference<Map<String, dynamic>> _statuses(String uid) =>
      _db.collection(FirestorePaths.userHouseholdStatus(uid));

  /// Firestore allows at most 30 values in a `whereIn`.
  static const int _maxIn = 30;

  /// The user's status documents for exactly these households (the ones on
  /// screen), keyed by household id. Missing ids have no status.
  Future<Map<String, Map<String, dynamic>>> fetchStatuses(
    String uid,
    Iterable<String> householdIds,
  ) async {
    final ids = householdIds.toSet().toList();
    final chunks = [
      for (var i = 0; i < ids.length; i += _maxIn)
        ids.sublist(i, i + _maxIn > ids.length ? ids.length : i + _maxIn),
    ];
    final snapshots = await Future.wait([
      for (final chunk in chunks)
        _statuses(uid).where(FieldPath.documentId, whereIn: chunk).get(),
    ]);
    return {
      for (final snapshot in snapshots)
        for (final doc in snapshot.docs) doc.id: doc.data(),
    };
  }

  /// Recorded owner names from the user's cached Melissa address checks
  /// (`users/{uid}/enrichment/{householdId}`), by household id.
  Future<Map<String, String>> fetchOwnerNames(String uid) async {
    final snap = await _db
        .collection('users')
        .doc(uid)
        .collection('enrichment')
        .limit(1000)
        .get();
    final out = <String, String>{};
    for (final doc in snap.docs) {
      final name = ownerNameOf(doc.data());
      if (name != null) out[doc.id] = name;
    }
    return out;
  }

  /// The owner name in an enrichment document or callable response.
  static String? ownerNameOf(Map<Object?, Object?> data) {
    final property = data['property'];
    if (property is! Map) return null;
    final owner = property['owner'];
    if (owner is! Map) return null;
    final name = owner['name']?.toString().trim() ?? '';
    return name.isEmpty ? null : name;
  }

  /// Live status changes made after [since] (on this or another device).
  /// Bounded to this session's changes, unlike a listener on every status.
  Stream<Map<String, Map<String, dynamic>>> watchStatusChanges(
    String uid, {
    required DateTime since,
  }) {
    return _statuses(uid)
        .where('updatedAt', isGreaterThanOrEqualTo: Timestamp.fromDate(since))
        .snapshots()
        .map(
          (snapshot) => {
            for (final change in snapshot.docChanges)
              if (change.type != DocumentChangeType.removed)
                change.doc.id: change.doc.data() ?? const {},
          },
        );
  }

  /// Totals for the user's statuses, counted on the server (billed one read
  /// per 1000 entries, no documents downloaded). Keys: `all`, `isPrayed`,
  /// `isVisited`, `isInvited`, `hasFollowUp`.
  Future<Map<String, int>> countStatuses(String uid) async {
    const flags = ['isPrayed', 'isVisited', 'isInvited', 'hasFollowUp'];
    final results = await Future.wait([
      _statuses(uid).count().get(),
      for (final flag in flags)
        _statuses(uid).where(flag, isEqualTo: true).count().get(),
    ]);
    return {
      'all': results[0].count ?? 0,
      for (var i = 0; i < flags.length; i++)
        flags[i]: results[i + 1].count ?? 0,
    };
  }

  /// A page of the user's status documents, most recently updated first.
  ///
  /// [onlyWhere] limits it to documents where that boolean field is true
  /// (e.g. `isPrayed`). That query needs a composite index
  /// (`firestore.indexes.json`); until the index exists, pages are built by
  /// scanning newest-first documents and filtering them here.
  Future<StatusPage> fetchStatusPage({
    required String uid,
    String? onlyWhere,
    int limit = 20,
    HouseholdSnapshot? startAfter,
  }) async {
    Query<Map<String, dynamic>> query = _db
        .collection(FirestorePaths.userHouseholdStatus(uid))
        .orderBy('updatedAt', descending: true);
    if (onlyWhere != null) {
      try {
        return await _page(
          query.where(onlyWhere, isEqualTo: true),
          limit,
          startAfter,
        );
      } on FirebaseException catch (error) {
        if (error.code != 'failed-precondition') rethrow;
        return _scanPage(query, onlyWhere, limit, startAfter);
      }
    }
    return _page(query, limit, startAfter);
  }

  Future<StatusPage> _page(
    Query<Map<String, dynamic>> query,
    int limit,
    HouseholdSnapshot? startAfter,
  ) async {
    if (startAfter != null) query = query.startAfterDocument(startAfter);
    // One extra document tells whether another page exists.
    final snapshot = await query.limit(limit + 1).get();
    final docs = snapshot.docs.take(limit).toList();
    return StatusPage(
      docs: docs,
      hasMore: snapshot.docs.length > limit,
      cursor: docs.isEmpty ? startAfter : docs.last,
    );
  }

  /// Fallback without the composite index: reads newest-first batches until
  /// [limit] matching documents (plus one, to know if there are more) are
  /// found or the collection ends.
  Future<StatusPage> _scanPage(
    Query<Map<String, dynamic>> query,
    String field,
    int limit,
    HouseholdSnapshot? startAfter,
  ) async {
    const batchSize = 50;
    final matches = <HouseholdSnapshot>[];
    var cursor = startAfter;
    HouseholdSnapshot? pageCursor = startAfter;
    while (true) {
      var batchQuery = query.limit(batchSize);
      if (cursor != null) batchQuery = batchQuery.startAfterDocument(cursor);
      final batch = await batchQuery.get();
      for (final doc in batch.docs) {
        cursor = doc;
        if (doc.data()[field] != true) continue;
        if (matches.length == limit) {
          return StatusPage(docs: matches, hasMore: true, cursor: pageCursor);
        }
        matches.add(doc);
        pageCursor = doc;
      }
      if (batch.docs.length < batchSize) {
        return StatusPage(docs: matches, hasMore: false, cursor: pageCursor);
      }
    }
  }

  /// Writes the user's status for [household] (merge: fields not written
  /// are kept). The resident name is written only when [nameChanged]: the
  /// new name, or deleted when removed.
  Future<void> saveStatus({
    required String uid,
    required HouseholdModel household,
    required bool wasPrayed,
    bool nameChanged = false,
    String? roundId,
  }) async {
    final data = <String, dynamic>{
      ...household.toStatusFirestore(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (nameChanged) {
      data['residentName'] = household.residentName ?? FieldValue.delete();
    }
    final event = roundId == null
        ? null
        : _db
              .collection(FirestorePaths.userPrayerLog(uid))
              .doc(FirestorePaths.prayerEventId(roundId, household.id));
    Future<void> Function()? history;
    if (household.isPrayed && !wasPrayed) {
      // Client time so "prayed today" is correct before the write syncs.
      final now = Timestamp.now();
      data['prayedAt'] = now;
      // History: one event per home per round, never overwritten by a
      // later round (the status keeps only the latest prayedAt).
      if (event != null) {
        history = () => event.set({
          'householdId': household.id,
          'roundId': roundId,
          'prayedAt': now,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
    } else if (!household.isPrayed) {
      data['prayedAt'] = FieldValue.delete();
      // Un-praying corrects this round's event; earlier rounds are kept.
      if (wasPrayed && event != null) history = event.delete;
    }

    final status = _db
        .collection(FirestorePaths.userHouseholdStatus(uid))
        .doc(household.id)
        .set(data, SetOptions(merge: true));
    // The history is written separately and its failure never fails the
    // prayer: rules deployed before `prayer_log` existed deny it, and the
    // status (what every screen reads) must still be saved.
    final logged = history?.call().catchError((Object _) {});
    await status;
    await logged;
  }

  /// The membership of a prayer round, or null when none is recorded.
  Future<PrayerRound?> fetchRound(String uid, String roundId) async {
    final doc = await _db
        .collection(FirestorePaths.userPrayerRounds(uid))
        .doc(roundId)
        .get();
    return PrayerRound.fromFirestore(doc.data());
  }

  /// Records (or replaces) the homes of a round.
  Future<void> saveRoundMembers(String uid, String roundId, PrayerRound round) {
    return _db
        .collection(FirestorePaths.userPrayerRounds(uid))
        .doc(roundId)
        .set({
          ...round.toFirestore(),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
  }

  /// Lifetime prayers from the history (every round), counted on the
  /// server.
  Future<int> countPrayerEvents(String uid) async {
    final result = await _db
        .collection(FirestorePaths.userPrayerLog(uid))
        .count()
        .get();
    return result.count ?? 0;
  }

  /// Prayer events of one round (or all rounds when [roundId] is null).
  Future<List<Map<String, dynamic>>> fetchPrayerEvents(
    String uid, {
    String? roundId,
  }) async {
    Query<Map<String, dynamic>> q = _db.collection(
      FirestorePaths.userPrayerLog(uid),
    );
    if (roundId != null) q = q.where('roundId', isEqualTo: roundId);
    final snap = await q.get();
    return [for (final d in snap.docs) d.data()];
  }
}
