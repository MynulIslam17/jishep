import 'package:get/get.dart';
import 'package:gps_cielo/core/data/user_repository.dart';
import 'package:gps_cielo/core/models/household_model.dart';
import 'package:gps_cielo/core/models/user_model.dart';
import 'package:gps_cielo/core/services/household_store.dart';
import 'package:gps_cielo/core/services/location_service.dart';
import 'package:gps_cielo/features/notifications/data/repositories/notification_repository.dart';

class HomeService {
  final HouseholdStore _store;
  final LocationService _locationService;
  final UserRepository _userRepository;
  final NotificationRepository _notificationRepository;

  HomeService(
    this._store,
    this._locationService,
    this._userRepository,
    this._notificationRepository,
  );

  RxList<HouseholdModel> get households => _store.households;

  RxBool get isLoading => _store.isLoading;

  /// Moves the user's search center to [address] and reloads nearby
  /// households. Pass [location] when coordinates are already known (from a
  /// suggestion or GPS) to skip geocoding. Returns the updated user.
  Future<UserModel> searchNeighborhood(
    UserModel user,
    String address, {
    ResolvedLocation? location,
  }) async {
    location ??= await _locationService.resolveAddress(address);
    final updated = user.copyWith(
      address: location.address,
      latitude: location.latitude,
      longitude: location.longitude,
    );

    await _userRepository.updateLocation(
      uid: user.id,
      address: location.address,
      latitude: location.latitude,
      longitude: location.longitude,
    );
    await _store.bindUser(updated);
    return updated;
  }

  Future<ResolvedLocation> currentLocation() {
    return _locationService.currentLocation();
  }

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
