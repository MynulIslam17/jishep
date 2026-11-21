import 'package:get/get.dart';
import 'package:gps_cielo/core/models/household_model.dart';
import 'package:gps_cielo/core/services/household_store.dart';
import 'package:gps_cielo/core/services/location_service.dart';

/// The Neighborhood tab: the nearest N homes around the saved home, or
/// around a place the user looks at for a while (a temporary search).
class NeighborhoodService {
  final HouseholdStore _store;
  final LocationService? _locationService;

  NeighborhoodService(this._store, {LocationService? locationService})
    : _locationService = locationService;

  Rxn<SearchCenter> get center => _store.center;

  /// The nearest N homes around the center — pins and list.
  RxList<HouseholdModel> get households => _store.households;

  /// No household data exists around the current center.
  RxBool get areaUnavailable => _store.areaUnavailable;

  RxBool get isLoading => _store.isLoading;

  Future<void> refreshHouseholds() => _store.refreshHouseholds();

  /// Searches around [address] (or [location] when the coordinates are
  /// already known from a suggestion or GPS). Temporary: the saved home
  /// address is not changed.
  Future<ResolvedLocation> searchNeighborhood(
    String address, {
    ResolvedLocation? location,
  }) async {
    location ??= await _locations.resolveAddress(address);
    await _store.searchAround(location);
    return location;
  }

  /// Goes back to the saved home address.
  Future<void> useSavedLocation() => _store.useSavedLocation();

  Future<ResolvedLocation> currentLocation() => _locations.currentLocation();

  LocationService get _locations {
    final service = _locationService;
    if (service == null) throw StateError('No LocationService');
    return service;
  }

  Future<void> togglePray(String householdId) {
    return _store.togglePray(householdId);
  }

  Future<void> updateHousehold(HouseholdModel household) {
    return _store.saveHousehold(household);
  }
}
