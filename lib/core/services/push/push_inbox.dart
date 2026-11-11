import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gps_cielo/core/constants/firestore_paths.dart';
import 'package:gps_cielo/core/services/push/push_messaging_client.dart';
import 'package:gps_cielo/core/services/push/push_payload.dart';
import 'package:gps_cielo/features/notifications/data/models/notification_model.dart';

/// Keeps push notifications in the user's in-app inbox
/// (`users/{uid}/notifications`), so they count toward the unread badge and
/// can be read later.
///
///  * Each push has one inbox document. Its id is the sender's
///    `notificationId` (when a server already wrote the inbox entry) or is
///    derived from the FCM message id, so a push seen twice (received, then
///    tapped) never makes two entries.
///  * A received push is stored unread; a tapped push is stored read, or its
///    existing entry is marked read.
///  * Fields match the Firestore rules for client-created notifications.
class PushInbox {
  PushInbox({FirebaseFirestore? firestore})
    : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  static const int maxTitle = 200;
  static const int maxMessage = 2000;
  static final RegExp _validServerId = RegExp(r'^[A-Za-z0-9_-]{1,128}$');

  /// The inbox document id for [message], or null when it can't be told
  /// apart from other pushes (no ids at all).
  static String? idFor(PushMessage message) {
    final serverId = message.data['notificationId']?.toString();
    if (serverId != null && _validServerId.hasMatch(serverId)) {
      return serverId;
    }
    final messageId = message.id;
    if (messageId == null || messageId.isEmpty) return null;
    final safe = messageId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    return 'push_${safe.length > 120 ? safe.substring(0, 120) : safe}';
  }

  /// A push arrived: add it unread unless it is already in the inbox.
  Future<void> recordReceived(String uid, PushMessage message) =>
      _record(uid, message, opened: false);

  /// A push was tapped: add it as read, or mark its entry read.
  Future<void> recordOpened(String uid, PushMessage message) =>
      _record(uid, message, opened: true);

  Future<void> _record(
    String uid,
    PushMessage message, {
    required bool opened,
  }) async {
    final id = idFor(message);
    final title = (message.title ?? '').trim();
    final body = (message.body ?? '').trim();
    if (id == null) return;

    final doc = _db.collection(FirestorePaths.userNotifications(uid)).doc(id);
    final existing = await doc.get();
    if (existing.exists) {
      if (opened && existing.data()?['isRead'] != true) {
        await doc.update({'isRead': true});
      }
      return;
    }
    // Nothing to show (a data-only message).
    if (title.isEmpty && body.isEmpty) return;

    final payload = PushPayload.fromData(message.data);
    await doc.set({
      'title': _cut(title.isEmpty ? 'GPS Para El Cielo' : title, maxTitle),
      'message': _cut(body, maxMessage),
      'type': (payload.type ?? NotificationType.churchNews).name,
      'isRead': opened,
      'actionRoute': payload.route,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  static String _cut(String s, int max) =>
      s.length <= max ? s : s.substring(0, max);
}
