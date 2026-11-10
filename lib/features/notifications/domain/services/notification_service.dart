import 'package:gps_cielo/features/notifications/data/repositories/notification_repository.dart';

class NotificationService {
  final NotificationRepository _repository;

  NotificationService(this._repository);

  /// The newest page, live.
  Stream<NotificationPage> watchLatest() => _repository.watchLatest();

  /// The newest page from the server.
  Future<NotificationPage> getLatest() => _repository.getLatest();

  /// The page older than [after].
  Future<NotificationPage> fetchOlder(NotificationCursor after) {
    return _repository.fetchOlder(after);
  }

  Future<void> markAsRead(String id) => _repository.markAsRead(id);

  Future<void> markAllAsRead() => _repository.markAllAsRead();

  Future<void> deleteNotification(String id) {
    return _repository.deleteNotification(id);
  }

  Future<void> clearAllNotifications() {
    return _repository.clearAllNotifications();
  }
}
