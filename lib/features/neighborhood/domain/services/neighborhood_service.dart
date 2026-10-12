import 'package:get/get.dart';
import 'package:gps_cielo/core/models/household_model.dart';
import 'package:gps_cielo/core/services/household_store.dart';

class NeighborhoodService {
  final HouseholdStore _store;

  NeighborhoodService(this._store);

  RxList<HouseholdModel> get households => _store.households;

  RxBool get isLoading => _store.isLoading;

  Future<void> refreshHouseholds() => _store.refreshHouseholds();

  Future<void> togglePray(String householdId) {
    return _store.togglePray(householdId);
  }

  Future<void> toggleVisit(String householdId) {
    return _store.toggleVisited(householdId);
  }

  Future<void> updateHousehold(HouseholdModel household) {
    return _store.saveHousehold(household);
  }
}
