import 'package:get/get.dart';
import 'package:gps_cielo/core/models/household_model.dart';
import 'package:gps_cielo/core/services/household_store.dart';

/// The Neighborhood tab: the nearest N homes around the saved primary
/// location (the only place the app searches; blueprint §2.1).
class NeighborhoodService {
  final HouseholdStore _store;

  NeighborhoodService(this._store);

  Rxn<SearchCenter> get center => _store.center;

  /// The nearest N homes around the center — pins and list.
  RxList<HouseholdModel> get households => _store.households;

  /// No household data exists around the current center.
  RxBool get areaUnavailable => _store.areaUnavailable;

  /// Where the homes came from (Melissa-first), or null.
  RxnString get areaSourceNote => _store.areaSourceNote;

  RxBool get isLoading => _store.isLoading;

  Future<void> refreshHouseholds() => _store.refreshHouseholds();

  Future<void> togglePray(String householdId) {
    return _store.togglePray(householdId);
  }

  Future<void> updateHousehold(HouseholdModel household) {
    return _store.saveHousehold(household);
  }
}
