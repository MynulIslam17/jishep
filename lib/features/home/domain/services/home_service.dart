import 'package:get/get.dart';
import 'package:gps_cielo/core/models/household_model.dart';
import 'package:gps_cielo/core/services/household_store.dart';
import 'package:gps_cielo/core/services/location_service.dart';
import 'package:gps_cielo/features/notifications/data/repositories/notification_repository.dart';

class HomeService {
  final HouseholdStore _store;
  final LocationService _locationService;
  final NotificationRepository _notificationRepository;

  HomeService(this._store, this._locationService, this._notificationRepository);

  RxList<HouseholdModel> get households => _store.households;

  RxBool get isLoading => _store.isLoading;

  Rxn<SearchCenter> get center => _store.center;

  RxnDouble get rangeMeters => _store.rangeMeters;

  /// Searches nearby households around [address] (or [location] when the
  /// coordinates are already known from a suggestion or GPS).
  ///
  /// This is a temporary search: the saved home address is not changed.
  Future<ResolvedLocation> searchNeighborhood(
    String address, {
    ResolvedLocation? location,
  }) async {
    location ??= await _locationService.resolveAddress(address);
    await _store.searchAround(location);
    return location;
  }

  RxInt get activeRadius => _store.activeRadius;

  RxBool get isRadiusFiltered => _store.isRadiusFiltered;

  RxInt get defaultHomes => _store.defaultHomes;

  RxInt get foundInRange => _store.foundInRange;

  /// False while only part of the range has been read ("N+ in range").
  RxBool get areaComplete => _store.areaComplete;

  /// Shows the [homes] nearest households within the range. Not saved; the
  /// default number and the range are set in Settings > My preferences.
  Future<void> filterRadius(int? homes) => _store.filterRadius(homes);

  Future<void> refreshHouseholds() => _store.refreshHouseholds();

  /// Goes back to searching around the saved home address.
  Future<void> useSavedLocation() => _store.useSavedLocation();

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
