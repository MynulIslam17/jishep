import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:gps_cielo/core/constants/firestore_paths.dart';
import 'package:gps_cielo/core/utils/api_debug_log.dart';
import 'package:gps_cielo/core/utils/firebase_error_mapper.dart';
import 'package:gps_cielo/features/notifications/data/models/notification_model.dart';

/// Firestore access for `users/{uid}/notifications`.
class NotificationRepository {
  final FirebaseFirestore _db;
  final FirebaseAuth _auth;

  NotificationRepository({FirebaseFirestore? firestore, FirebaseAuth? auth})
      : _db = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  CollectionReference<Map<String, dynamic>> get _collection {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw const AppException('You are not signed in.');
    return _db.collection(FirestorePaths.userNotifications(uid));
  }

  Query<Map<String, dynamic>> get _ordered =>
      _collection.orderBy('timestamp', descending: true).limit(100);

  Stream<List<NotificationModel>> watchNotifications() {
    return ApiDebugLog.stream(
      'NotificationRepository.watchNotifications',
      _ordered.snapshots().map(_mapDocs),
    );
  }

  Future<List<NotificationModel>> getNotifications() {
    return ApiDebugLog.run('NotificationRepository.getNotifications', () async {
      final snapshot =
          await _ordered.get(const GetOptions(source: Source.server));
      return _mapDocs(snapshot);
    });
  }

  Stream<int> watchUnreadCount() {
    return ApiDebugLog.stream(
      'NotificationRepository.watchUnreadCount',
      _collection
          .where('isRead', isEqualTo: false)
          .snapshots()
          .map((snapshot) => snapshot.size),
    );
  }

  Future<void> addNotification({
    required String title,
    required String message,
    required NotificationType type,
    String? actionRoute,
  }) {
    return ApiDebugLog.run(
      'NotificationRepository.addNotification',
      () => _collection.add({
        'title': title,
        'message': message,
        'type': type.name,
        'isRead': false,
        'actionRoute': actionRoute,
        'timestamp': FieldValue.serverTimestamp(),
      }),
      details: type.name,
    );
  }

  Future<void> markAsRead(String id) {
    return ApiDebugLog.run(
      'NotificationRepository.markAsRead',
      () => _collection.doc(id).update({'isRead': true}),
      details: id,
    );
  }

  Future<void> markAllAsRead() {
    return ApiDebugLog.run('NotificationRepository.markAllAsRead', () async {
      final unread = await _collection.where('isRead', isEqualTo: false).get();
      await _commitInChunks(
        unread.docs,
        (batch, doc) => batch.update(doc.reference, {'isRead': true}),
      );
    });
  }

  Future<void> deleteNotification(String id) {
    return ApiDebugLog.run(
      'NotificationRepository.deleteNotification',
      () => _collection.doc(id).delete(),
      details: id,
    );
  }

  Future<void> clearAllNotifications() {
    return ApiDebugLog.run(
      'NotificationRepository.clearAllNotifications',
      () async {
        final all = await _collection.get();
        await _commitInChunks(
          all.docs,
          (batch, doc) => batch.delete(doc.reference),
        );
      },
    );
  }

  Future<void> _commitInChunks(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    void Function(WriteBatch batch, QueryDocumentSnapshot<Map<String, dynamic>> doc) apply,
  ) async {
    const chunkSize = 450;
    for (var i = 0; i < docs.length; i += chunkSize) {
      final batch = _db.batch();
      for (final doc in docs.skip(i).take(chunkSize)) {
        apply(batch, doc);
      }
      await batch.commit();
    }
  }

  List<NotificationModel> _mapDocs(QuerySnapshot<Map<String, dynamic>> snapshot) {
    return snapshot.docs.map(NotificationModel.fromFirestore).toList();
  }
}
