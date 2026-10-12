import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gps_cielo/core/constants/firestore_paths.dart';
import 'package:gps_cielo/core/models/user_model.dart';
import 'package:gps_cielo/core/utils/api_debug_log.dart';

/// Reads and writes the `users/{uid}` profile document.
class UserRepository {
  final FirebaseFirestore _db;

  UserRepository({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> _doc(String uid) =>
      _db.doc(FirestorePaths.user(uid));

  Future<UserModel?> getUser(String uid) {
    return ApiDebugLog.run('UserRepository.getUser', () async {
      final snapshot = await _doc(uid).get();
      if (!snapshot.exists) return null;
      return UserModel.fromFirestore(snapshot);
    }, details: uid);
  }

  Stream<UserModel?> watchUser(String uid) {
    return ApiDebugLog.stream(
      'UserRepository.watchUser',
      _doc(uid).snapshots().map(
            (snapshot) =>
                snapshot.exists ? UserModel.fromFirestore(snapshot) : null,
          ),
      details: uid,
    );
  }

  Future<void> createUser(UserModel user) {
    return ApiDebugLog.run(
      'UserRepository.createUser',
      () => _doc(user.id).set({
        ...user.toFirestore(),
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true)),
      details: user.id,
    );
  }

  Future<void> updateFields(String uid, Map<String, dynamic> fields) {
    return ApiDebugLog.run(
      'UserRepository.updateFields',
      () => _doc(uid).set({
        ...fields,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true)),
      details: '$uid ${fields.keys.join(',')}',
    );
  }

  Future<void> updateLocation({
    required String uid,
    required String address,
    required double latitude,
    required double longitude,
    int? radiusHomes,
  }) {
    return updateFields(uid, {
      'address': address,
      'latitude': latitude,
      'longitude': longitude,
      'radiusHomes': ?radiusHomes,
    });
  }

  /// Saves a small base64 JPEG on the profile document. Firebase Storage is
  /// not used so the project can stay on the free Spark plan.
  Future<void> saveAvatar(String uid, String base64Jpeg) {
    return updateFields(uid, {'avatarBase64': base64Jpeg});
  }

  /// Deletes the profile and every per-user subcollection document.
  Future<void> deleteUserData(String uid) {
    return ApiDebugLog.run('UserRepository.deleteUserData', () async {
      for (final path in [
        FirestorePaths.userHouseholdStatus(uid),
        FirestorePaths.userNotifications(uid),
      ]) {
        while (true) {
          final page = await _db.collection(path).limit(400).get();
          if (page.docs.isEmpty) break;
          final batch = _db.batch();
          for (final doc in page.docs) {
            batch.delete(doc.reference);
          }
          await batch.commit();
        }
      }
      await _doc(uid).delete();
    }, details: uid);
  }

  Future<void> sendSupportMessage({
    required String uid,
    required String email,
    required String message,
  }) {
    return ApiDebugLog.run(
      'UserRepository.sendSupportMessage',
      () => _db.collection(FirestorePaths.supportMessages).add({
        'uid': uid,
        'email': email,
        'message': message,
        'status': 'open',
        'createdAt': FieldValue.serverTimestamp(),
      }),
      details: uid,
    );
  }
}
