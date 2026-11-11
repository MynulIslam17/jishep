import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gps_cielo/core/constants/firestore_paths.dart';

/// Where push notifications can reach a user: `users/{uid}/devices/{token}`.
///
/// The FCM token is the document id, so a device is stored once per account
/// however often it registers, and a user can have several devices. Only
/// the owner can read or write these (see firestore.rules); a server (Admin
/// SDK) reads them to send notifications.
class DeviceTokenRepository {
  final FirebaseFirestore _db;

  DeviceTokenRepository({FirebaseFirestore? firestore})
    : _db = firestore ?? FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> _doc(String uid, String token) =>
      _db.collection(FirestorePaths.userDevices(uid)).doc(token);

  /// Registers (or refreshes) [token] for [uid].
  Future<void> save({
    required String uid,
    required String token,
    required String platform,
  }) {
    return _doc(uid, token).set({
      'token': token,
      'platform': platform,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Stops sending to [token] for [uid] (sign-out, or a replaced token).
  Future<void> delete({required String uid, required String token}) {
    return _doc(uid, token).delete();
  }
}
