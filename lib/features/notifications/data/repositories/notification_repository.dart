import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:gps_cielo/core/constants/firestore_paths.dart';
import 'package:gps_cielo/core/utils/firebase_error_mapper.dart';
import 'package:gps_cielo/features/notifications/data/models/notification_model.dart';

typedef NotificationCursor = DocumentSnapshot<Map<String, dynamic>>;

/// One page of notifications, newest first.
class NotificationPage {
  const NotificationPage({
    required this.items,
    required this.hasMore,
    this.cursor,
  });

  final List<NotificationModel> items;

  /// True when older notifications may follow [cursor].
  final bool hasMore;
  final NotificationCursor? cursor;
}

/// Firestore access for `users/{uid}/notifications`.
///
/// Reads are bounded: the screen listens to the newest [pageSize] and reads
/// older ones a page at a time; the Home badge counts at most
/// [unreadCountCap] unread (shown as "99+").
class NotificationRepository {
  static const int pageSize = 30;
  static const int unreadCountCap = 100;

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
      _collection.orderBy('timestamp', descending: true);

  /// The newest [limit] notifications, live.
  Stream<NotificationPage> watchLatest({int limit = pageSize}) {
    return _ordered.limit(limit).snapshots().map((s) => _page(s, limit));
  }

  /// The newest [limit] notifications from the server (pull to refresh).
  Future<NotificationPage> getLatest({int limit = pageSize}) async {
    final snapshot = await _ordered
        .limit(limit)
        .get(const GetOptions(source: Source.server));
    return _page(snapshot, limit);
  }

  /// The [limit] notifications older than [after].
  Future<NotificationPage> fetchOlder(
    NotificationCursor after, {
    int limit = pageSize,
  }) async {
    final snapshot = await _ordered
        .startAfterDocument(after)
        .limit(limit)
        .get();
    return _page(snapshot, limit);
  }

  /// Unread notifications, counted up to [unreadCountCap].
  Stream<int> watchUnreadCount() {
    return _collection
        .where('isRead', isEqualTo: false)
        .limit(unreadCountCap)
        .snapshots()
        .map((snapshot) => snapshot.size);
  }

  NotificationPage _page(QuerySnapshot<Map<String, dynamic>> s, int limit) {
    return NotificationPage(
      items: _mapDocs(s),
      hasMore: s.docs.length >= limit,
      cursor: s.docs.isEmpty ? null : s.docs.last,
    );
  }

  Future<void> addNotification({
    required String title,
    required String message,
    required NotificationType type,
    String? actionRoute,
  }) {
    return _collection.add({
      'title': title,
      'message': message,
      'type': type.name,
      'isRead': false,
      'actionRoute': actionRoute,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  Future<void> markAsRead(String id) {
    return _collection.doc(id).update({'isRead': true});
  }

  /// Marks every unread notification read, 450 per batch (never holding
  /// them all in memory).
  Future<void> markAllAsRead() async {
    final unread = _collection.where('isRead', isEqualTo: false);
    while (true) {
      final chunk = await unread.limit(_chunkSize).get();
      if (chunk.docs.isEmpty) return;
      await _commitInChunks(
        chunk.docs,
        (batch, doc) => batch.update(doc.reference, {'isRead': true}),
      );
      if (chunk.docs.length < _chunkSize) return;
    }
  }

  Future<void> deleteNotification(String id) {
    return _collection.doc(id).delete();
  }

  /// Deletes every notification, 450 per batch.
  Future<void> clearAllNotifications() async {
    while (true) {
      final chunk = await _collection.limit(_chunkSize).get();
      if (chunk.docs.isEmpty) return;
      await _commitInChunks(
        chunk.docs,
        (batch, doc) => batch.delete(doc.reference),
      );
      if (chunk.docs.length < _chunkSize) return;
    }
  }

  static const int _chunkSize = 450;

  Future<void> _commitInChunks(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    void Function(
      WriteBatch batch,
      QueryDocumentSnapshot<Map<String, dynamic>> doc,
    )
    apply,
  ) async {
    for (var i = 0; i < docs.length; i += _chunkSize) {
      final batch = _db.batch();
      for (final doc in docs.skip(i).take(_chunkSize)) {
        apply(batch, doc);
      }
      await batch.commit();
    }
  }

  List<NotificationModel> _mapDocs(
    QuerySnapshot<Map<String, dynamic>> snapshot,
  ) {
    return snapshot.docs.map(NotificationModel.fromFirestore).toList();
  }
}
