import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geoflutterfire_plus/geoflutterfire_plus.dart';
import 'package:gps_cielo/core/constants/firestore_paths.dart';
import 'package:gps_cielo/core/models/household_model.dart';
import 'package:gps_cielo/core/utils/api_debug_log.dart';

typedef HouseholdSnapshot = DocumentSnapshot<Map<String, dynamic>>;

/// Firestore access for the shared household directory and the signed-in
/// user's per-household status documents.
class HouseholdRepository {
  final FirebaseFirestore _db;

  HouseholdRepository({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  /// Search radii tried in order until enough households are found.
  static const List<double> _searchRadiiKm = [0.5, 2, 5, 15, 50];

  CollectionReference<Map<String, dynamic>> get _households =>
      _db.collection(FirestorePaths.households);

  /// Returns the [count] households closest to the given point, nearest first.
  ///
  /// Household documents must store `geo: {geohash, geopoint}` (see
  /// `tool/seed_households.js`).
  Future<List<HouseholdSnapshot>> fetchNearest({
    required double latitude,
    required double longitude,
    required int count,
  }) async {
    final center = GeoFirePoint(GeoPoint(latitude, longitude));
    final geoCollection = GeoCollectionReference<Map<String, dynamic>>(
      _households,
    );

    return ApiDebugLog.run(
      'HouseholdRepository.fetchNearest',
      () async {
        List<GeoDocumentSnapshot<Map<String, dynamic>>> results = const [];
        for (final radius in _searchRadiiKm) {
          results = await geoCollection.fetchWithinWithDistance(
            center: center,
            radiusInKm: radius,
            field: 'geo',
            geopointFrom: _geopointFrom,
            strictMode: true,
          );
          if (results.length >= count) break;
        }

        return results
            .take(count)
            .map((result) => result.documentSnapshot)
            .toList();
      },
      details: '$latitude,$longitude count=$count',
    );
  }

  /// Streams every status document of the user, keyed by household id.
  Stream<Map<String, Map<String, dynamic>>> watchStatuses(String uid) {
    return ApiDebugLog.stream(
      'HouseholdRepository.watchStatuses',
      _db
          .collection(FirestorePaths.userHouseholdStatus(uid))
          .snapshots()
          .map((snapshot) {
        return {
          for (final doc in snapshot.docs) doc.id: doc.data(),
        };
      }),
      details: uid,
    );
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

    return ApiDebugLog.run(
      'HouseholdRepository.saveStatus',
      () => _db
          .collection(FirestorePaths.userHouseholdStatus(uid))
          .doc(household.id)
          .set(data, SetOptions(merge: true)),
      details: '${household.id} prayed=${household.isPrayed}',
    );
  }

  static GeoPoint _geopointFrom(Map<String, dynamic> data) {
    final geo = data['geo'];
    final point = geo is Map ? geo['geopoint'] : null;
    return point is GeoPoint ? point : const GeoPoint(0, 0);
  }
}
