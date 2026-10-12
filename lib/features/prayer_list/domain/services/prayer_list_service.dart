import 'package:get/get.dart';
import 'package:gps_cielo/core/models/household_model.dart';
import 'package:gps_cielo/core/services/household_store.dart';

class PrayerListService {
  final HouseholdStore _store;

  PrayerListService(this._store);

  RxList<HouseholdModel> get households => _store.households;

  RxBool get isLoading => _store.isLoading;

  RxInt get totalPrayed => _store.prayedCount;

  Future<void> refreshHouseholds() => _store.refreshHouseholds();

  /// Today's list: households prayed for today, topped up with the nearest
  /// households not yet prayed for until [dailyTarget] is reached.
  static List<HouseholdModel> buildTodayList(
    List<HouseholdModel> households,
    int dailyTarget, {
    DateTime? now,
  }) {
    now ??= DateTime.now();
    final startOfToday = DateTime(now.year, now.month, now.day);

    final today = households
        .where(
          (h) =>
              h.isPrayed &&
              h.prayedAt != null &&
              !h.prayedAt!.isBefore(startOfToday),
        )
        .toList();

    for (final household in households) {
      if (today.length >= dailyTarget) break;
      if (!household.isPrayed) today.add(household);
    }

    today.sort((a, b) => a.number.compareTo(b.number));
    return today;
  }

  Future<void> togglePray(String householdId) {
    return _store.togglePray(householdId);
  }

  Future<void> toggleVisited(String householdId) {
    return _store.toggleVisited(householdId);
  }

  Future<void> toggleFollowUp(String householdId) {
    return _store.toggleFollowUp(householdId);
  }

  Future<void> updateHousehold(HouseholdModel household) {
    return _store.saveHousehold(household);
  }
}
