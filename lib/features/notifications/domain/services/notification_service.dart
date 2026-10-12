import 'package:gps_cielo/features/notifications/data/models/notification_model.dart';
import 'package:gps_cielo/features/notifications/data/repositories/notification_repository.dart';

class NotificationService {
  final NotificationRepository _repository;

  NotificationService(this._repository);

  Stream<List<NotificationModel>> watchNotifications() {
    return _repository.watchNotifications();
  }

  Future<List<NotificationModel>> getNotifications() {
    return _repository.getNotifications();
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
