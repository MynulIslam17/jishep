import 'package:get/get.dart';
import 'package:gps_cielo/core/models/household_model.dart';
import 'package:gps_cielo/core/services/household_store.dart';

class NeighborhoodService {
  final HouseholdStore _store;

  NeighborhoodService(this._store);

  Rxn<SearchCenter> get center => _store.center;

  RxnDouble get rangeMeters => _store.rangeMeters;

  RxInt get activeRadius => _store.activeRadius;

  /// Nearest few (the Home count) — the map pins.
  RxList<HouseholdModel> get households => _store.households;

  /// Households within the range read so far, nearest first — the paged
  /// list.
  RxList<HouseholdModel> get areaHouseholds => _store.areaHouseholds;

  /// True once every household within the range has been read.
  RxBool get areaComplete => _store.areaComplete;

  RxBool get isLoadingArea => _store.isLoadingArea;

  /// Reads further out until [count] households are known.
  Future<void> loadMoreArea(int count) => _store.loadMoreArea(count);

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
