import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gps_cielo/core/constants/firestore_paths.dart';
import 'package:gps_cielo/core/models/user_model.dart';

/// Reads and writes the `users/{uid}` profile document.
class UserRepository {
  final FirebaseFirestore _db;

  UserRepository({FirebaseFirestore? firestore})
    : _db = firestore ?? FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> _doc(String uid) =>
      _db.doc(FirestorePaths.user(uid));

  Future<UserModel?> getUser(String uid) async {
    final snapshot = await _doc(uid).get();
    if (!snapshot.exists) return null;
    return UserModel.fromFirestore(snapshot);
  }

  Stream<UserModel?> watchUser(String uid) {
    return _doc(uid).snapshots().map(
      (snapshot) => snapshot.exists ? UserModel.fromFirestore(snapshot) : null,
    );
  }

  /// Creates the profile only if it does not exist and returns the stored one.
  Future<UserModel> createUser(UserModel user) {
    final doc = _doc(user.id);
    return _db.runTransaction((transaction) async {
      final snapshot = await transaction.get(doc);
      if (snapshot.exists) return UserModel.fromFirestore(snapshot);

      transaction.set(doc, {
        ...user.toFirestore(),
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return user;
    });
  }

  Future<void> updateFields(String uid, Map<String, dynamic> fields) {
    return _doc(uid).set({
      ...fields,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
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
  Future<void> deleteUserData(String uid) async {
    await _deleteCollection(FirestorePaths.userHouseholdStatus(uid));
    await _deleteCollection(FirestorePaths.userNotifications(uid));
    // Push-token documents are optional clean-up: rules deployed before
    // `devices` existed deny access, which must not block deletion.
    await _deleteCollection(FirestorePaths.userDevices(uid), optional: true);
    await _deleteSupportMessages(uid);
    await _doc(uid).delete();
  }

  Future<void> _deleteCollection(String path, {bool optional = false}) async {
    try {
      while (true) {
        final page = await _db.collection(path).limit(400).get();
        if (page.docs.isEmpty) break;
        final batch = _db.batch();
        for (final doc in page.docs) {
          batch.delete(doc.reference);
        }
        await batch.commit();
      }
    } on FirebaseException catch (e) {
      if (!optional || e.code != 'permission-denied') rethrow;
    }
  }

  /// The user's own Contact Support messages.
  Future<void> _deleteSupportMessages(String uid) async {
    final messages = _db
        .collection(FirestorePaths.supportMessages)
        .where('uid', isEqualTo: uid);
    try {
      while (true) {
        final page = await messages.limit(400).get();
        if (page.docs.isEmpty) break;
        final batch = _db.batch();
        for (final doc in page.docs) {
          batch.delete(doc.reference);
        }
        await batch.commit();
      }
    } on FirebaseException catch (e) {
      // Rules that predate owner delete must not block account deletion.
      if (e.code != 'permission-denied') rethrow;
    }
  }

  Future<void> sendSupportMessage({
    required String uid,
    required String email,
    required String message,
  }) {
    return _db.collection(FirestorePaths.supportMessages).add({
      'uid': uid,
      'email': email,
      'message': message,
      'status': 'open',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }
}
