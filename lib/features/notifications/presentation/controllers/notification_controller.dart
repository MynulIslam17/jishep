import 'dart:async';

import 'package:get/get.dart';
import 'package:gps_cielo/core/services/push/push_payload.dart';
import 'package:gps_cielo/core/utils/firebase_error_mapper.dart';
import 'package:gps_cielo/core/utils/show_snackbar.dart';
import 'package:gps_cielo/features/notifications/data/models/notification_model.dart';
import 'package:gps_cielo/features/notifications/data/repositories/notification_repository.dart';
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

  /// The newest page (live) followed by older pages read on scroll.
  final notifications = <NotificationModel>[].obs;
  final selectedFilter = NotificationFilter.all.obs;
  final isLoading = false.obs;

  /// Older notifications may exist beyond those loaded.
  final hasMore = false.obs;
  final isLoadingMore = false.obs;

  List<NotificationModel> _latest = const [];
  final List<NotificationModel> _older = [];
  final Set<String> _removed = {};

  /// Where the newest page ends, and where older pages continue from.
  NotificationCursor? _latestCursor;
  NotificationCursor? _olderCursor;
  bool _latestHasMore = false;
  bool _olderHasMore = true;

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

  StreamSubscription<NotificationPage>? _subscription;

  @override
  void onInit() {
    super.onInit();
    isLoading.value = true;
    _subscription = _service.watchLatest().listen(
      (page) {
        _applyLatest(page);
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

  void _applyLatest(NotificationPage page) {
    if (_older.isNotEmpty) {
      // Pushed out of the live page by newer ones: they sit between the
      // live page and the older pages, so keep them.
      final live = {for (final n in page.items) n.id};
      final kept = {for (final n in _older) n.id};
      _older
        ..insertAll(0, [
          for (final n in _latest)
            if (!live.contains(n.id) && !kept.contains(n.id)) n,
        ])
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    }
    _latest = page.items;
    _latestCursor = page.cursor;
    _latestHasMore = page.hasMore;
    _publish();
  }

  /// Newest page first, then older pages, without duplicates (a
  /// notification can move between them as new ones arrive) and without
  /// those deleted here.
  void _publish() {
    final seen = <String>{};
    final local = {for (final n in notifications) n.id: n};
    notifications.assignAll([
      for (final n in [..._latest, ..._older])
        if (!_removed.contains(n.id) && seen.add(n.id))
          // Keep a read mark made here until the server echoes it.
          (local[n.id]?.isRead == true && !n.isRead)
              ? n.copyWith(isRead: true)
              : n,
    ]);
    hasMore.value = _older.isEmpty ? _latestHasMore : _olderHasMore;
  }

  /// Reads the next page of older notifications.
  Future<void> loadMore() async {
    if (!hasMore.value || isLoadingMore.value || isLoading.value) return;
    final after = _older.isEmpty ? _latestCursor : _olderCursor;
    if (after == null) return;
    isLoadingMore.value = true;
    try {
      final page = await _service.fetchOlder(after);
      _older.addAll(page.items);
      if (page.cursor != null) _olderCursor = page.cursor;
      _olderHasMore = page.hasMore;
      _publish();
    } catch (error) {
      SnackbarService.showError(
        'Notifications',
        FirebaseErrorMapper.message(error),
      );
    } finally {
      isLoadingMore.value = false;
    }
  }

  /// Pull-to-refresh: fetches the newest page from the server and drops
  /// older pages (read again on scroll).
  Future<void> loadNotifications() async {
    try {
      final page = await _service.getLatest();
      _older.clear();
      _olderCursor = null;
      _olderHasMore = true;
      _applyLatest(page);
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
      SnackbarService.showSuccess(
        'All Caught Up',
        'Marked all notifications as read.',
      );
    }
  }

  Future<void> deleteNotification(String id) async {
    _removed.add(id);
    notifications.removeWhere((n) => n.id == id);
    await _run(() => _service.deleteNotification(id));
  }

  Future<void> clearAll() async {
    if (notifications.isEmpty) return;
    _removed.addAll(notifications.map((n) => n.id));
    _older.clear();
    notifications.clear();
    hasMore.value = false;
    if (await _run(_service.clearAllNotifications)) {
      SnackbarService.showSuccess(
        'Cleared',
        'All notifications have been removed.',
      );
    }
  }

  void handleNotificationTap(NotificationModel item) {
    markAsRead(item.id);
    final route = item.actionRoute;
    // Only known screens: an old or unexpected route (for example a screen
    // that was removed) leaves the user on the inbox instead of failing.
    if (route == null || !PushPayload.allowedRoutes.contains(route)) return;

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
