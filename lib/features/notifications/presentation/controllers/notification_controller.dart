import 'dart:async';

import 'package:get/get.dart';
import 'package:gps_cielo/core/utils/firebase_error_mapper.dart';
import 'package:gps_cielo/core/utils/show_snackbar.dart';
import 'package:gps_cielo/features/notifications/data/models/notification_model.dart';
import 'package:gps_cielo/features/main_nav/presentation/controllers/main_nav_controller.dart';
import 'package:gps_cielo/features/main_nav/presentation/models/main_nav_destination.dart';
import 'package:gps_cielo/features/notifications/domain/services/notification_service.dart';
import 'package:gps_cielo/routes/app_routes.dart';

enum NotificationFilter {
  all('All'),
  unread('Unread'),
  prayers('Prayers'),
  announcements('News');

  final String label;
  const NotificationFilter(this.label);
}

class NotificationController extends GetxController {
  final NotificationService _service;

  NotificationController(this._service);

  final notifications = <NotificationModel>[].obs;
  final selectedFilter = NotificationFilter.all.obs;
  final isLoading = false.obs;

  int get unreadCount => notifications.where((n) => !n.isRead).length;

  List<NotificationModel> get filteredNotifications {
    return notifications.where((item) {
      return switch (selectedFilter.value) {
        NotificationFilter.all => true,
        NotificationFilter.unread => !item.isRead,
        NotificationFilter.prayers =>
          item.type == NotificationType.prayerReminder ||
              item.type == NotificationType.followUpDue,
        NotificationFilter.announcements =>
          item.type == NotificationType.churchNews ||
              item.type == NotificationType.milestone ||
              item.type == NotificationType.scripture,
      };
    }).toList();
  }

  StreamSubscription<List<NotificationModel>>? _subscription;

  @override
  void onInit() {
    super.onInit();
    isLoading.value = true;
    _subscription = _service.watchNotifications().listen(
      (list) {
        notifications.assignAll(list);
        isLoading.value = false;
      },
      onError: (Object error) {
        isLoading.value = false;
        SnackbarService.showError(
          'Notifications',
          FirebaseErrorMapper.message(error),
        );
      },
    );
  }

  /// Pull-to-refresh: fetches the latest notifications from the server.
  Future<void> loadNotifications() async {
    try {
      notifications.assignAll(await _service.getNotifications());
    } catch (error) {
      SnackbarService.showError(
        'Notifications',
        FirebaseErrorMapper.message(error),
      );
    }
  }

  void selectFilter(NotificationFilter filter) {
    selectedFilter.value = filter;
  }

  Future<void> markAsRead(String id) async {
    final index = notifications.indexWhere((n) => n.id == id);
    if (index != -1 && !notifications[index].isRead) {
      notifications[index] = notifications[index].copyWith(isRead: true);
      await _run(() => _service.markAsRead(id));
    }
  }

  Future<void> markAllAsRead() async {
    if (unreadCount == 0) return;

    notifications.assignAll(
      notifications.map((n) => n.copyWith(isRead: true)).toList(),
    );
    if (await _run(_service.markAllAsRead)) {
      SnackbarService.showSuccess('All Caught Up', 'Marked all notifications as read.');
    }
  }

  Future<void> deleteNotification(String id) async {
    notifications.removeWhere((n) => n.id == id);
    await _run(() => _service.deleteNotification(id));
  }

  Future<void> clearAll() async {
    if (notifications.isEmpty) return;
    notifications.clear();
    if (await _run(_service.clearAllNotifications)) {
      SnackbarService.showSuccess('Cleared', 'All notifications have been removed.');
    }
  }

  void handleNotificationTap(NotificationModel item) {
    markAsRead(item.id);
    final route = item.actionRoute;
    if (route == null || route.isEmpty) return;

    // Tab destinations live inside MainNav; switch tabs instead of pushing.
    final tab = _tabRoutes[route];
    if (tab != null && Get.isRegistered<MainNavController>()) {
      Get.back();
      Get.find<MainNavController>().changeDestination(tab);
      return;
    }
    Get.toNamed(route);
  }

  static const Map<String, MainNavDestination> _tabRoutes = {
    AppRoutes.home: MainNavDestination.home,
    AppRoutes.neighborhood: MainNavDestination.neighborhood,
    AppRoutes.prayerList: MainNavDestination.prayerList,
    AppRoutes.followUp: MainNavDestination.followUp,
    AppRoutes.profile: MainNavDestination.profile,
  };

  Future<bool> _run(Future<void> Function() action) async {
    try {
      await action();
      return true;
    } catch (error) {
      SnackbarService.showError(
        'Notifications',
        FirebaseErrorMapper.message(error),
      );
      return false;
    }
  }

  @override
  void onClose() {
    _subscription?.cancel();
    super.onClose();
  }
}
