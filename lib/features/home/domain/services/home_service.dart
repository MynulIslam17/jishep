import 'package:get/get.dart';
import 'package:gps_cielo/core/models/household_model.dart';
import 'package:gps_cielo/core/services/household_store.dart';
import 'package:gps_cielo/features/notifications/data/repositories/notification_repository.dart';

class HomeService {
  final HouseholdStore _store;
  final NotificationRepository _notificationRepository;

  HomeService(this._store, this._notificationRepository);

  /// "My neighborhood" around the saved home (the Prayer List's homes).
  RxList<HouseholdModel> get neighborhood => _store.homeHouseholds;

  /// Where the neighborhood came from, or why it is empty (Melissa only).
  RxnString get homeSourceNote => _store.homeSourceNote;

  RxBool get isLoading => _store.isLoading;

  /// No household data exists around the saved home.
  RxBool get homeUnavailable => _store.homeUnavailable;

  /// Reloads "my neighborhood" (around the saved home).
  Future<void> refreshNeighborhood() => _store.refreshHome();

  Future<void> togglePray(String householdId) {
    return _store.togglePray(householdId);
  }

  Future<void> updateHousehold(HouseholdModel household) {
    return _store.saveHousehold(household);
  }

  Stream<int> watchUnreadNotificationCount() {
    return _notificationRepository.watchUnreadCount();
  }
}
