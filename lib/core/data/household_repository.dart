import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gps_cielo/core/data/geo_search.dart';
import 'package:gps_cielo/core/constants/firestore_paths.dart';
import 'package:gps_cielo/core/models/household_model.dart';

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

  HouseholdRepository({FirebaseFirestore? firestore})
    : _db = firestore ?? FirebaseFirestore.instance;

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

  Future<void> saveStatus({
    required String uid,
    required HouseholdModel household,
    required bool wasPrayed,
  }) {
    final data = <String, dynamic>{
      ...household.toStatusFirestore(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (household.isPrayed && !wasPrayed) {
      // Client time so "prayed today" is correct before the write syncs.
      data['prayedAt'] = Timestamp.now();
    } else if (!household.isPrayed) {
      data['prayedAt'] = FieldValue.delete();
    }

    return _db
        .collection(FirestorePaths.userHouseholdStatus(uid))
        .doc(household.id)
        .set(data, SetOptions(merge: true));
  }
}
