import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:get/get.dart';
import 'package:gps_cielo/core/data/user_repository.dart';
import 'package:gps_cielo/core/models/household_model.dart';
import 'package:gps_cielo/core/services/household_store.dart';

/// Today's prayers and the prayer cycle, worked out from "my neighborhood":
/// the Settings number of households within the Settings range around the
/// saved home ([HouseholdStore.homeHouseholds]).
class PrayerPlan {
  /// Today's households: those already prayed for today, then the nearest
  /// not yet prayed for in this cycle, up to the daily target.
  final List<HouseholdModel> today;
  final int prayedToday;
  final int dailyTarget;

  /// Households in the neighborhood prayed for in this cycle / all of them.
  final int cyclePrayed;
  final int cycleTotal;

  const PrayerPlan({
    required this.today,
    required this.prayedToday,
    required this.dailyTarget,
    required this.cyclePrayed,
    required this.cycleTotal,
  });

  static const empty = PrayerPlan(
    today: [],
    prayedToday: 0,
    dailyTarget: 0,
    cyclePrayed: 0,
    cycleTotal: 0,
  );

  int get cycleRemaining => cycleTotal - cyclePrayed;

  /// Every household in the neighborhood has been prayed for this cycle.
  bool get isCycleComplete => cycleTotal > 0 && cyclePrayed >= cycleTotal;

  /// Today's target reached (or nothing left to pray for in this cycle).
  bool get isTodayDone => today.isNotEmpty && today.every((h) => h.isPrayed);

  /// Days left in the cycle at the daily target (today included).
  int get daysLeft =>
      dailyTarget <= 0 ? 0 : (cycleRemaining / dailyTarget).ceil();
}

class PrayerListService {
  final HouseholdStore _store;
  final UserRepository _users;

  PrayerListService(this._store, this._users);

  RxList<HouseholdModel> get neighborhood => _store.homeHouseholds;

  RxBool get isLoading => _store.isLoading;

  Rxn<DateTime> get cycleStartedAt => _store.cycleStartedAt;

  RxnDouble get rangeMeters => _store.rangeMeters;

  /// Reloads "my neighborhood" (around the saved home).
  Future<void> refreshHouseholds() => _store.refreshHome();

  static PrayerPlan buildPlan(
    List<HouseholdModel> neighborhood,
    int dailyTarget, {
    DateTime? now,
  }) {
    now ??= DateTime.now();
    final prayedToday = [
      for (final h in neighborhood)
        if (h.prayedOn(now)) h,
    ];
    final notYet = [
      for (final h in neighborhood)
        if (!h.isPrayed) h,
    ];
    final slots = math.max(0, dailyTarget - prayedToday.length);
    final today = [...prayedToday, ...notYet.take(slots)]
      ..sort((a, b) => a.number.compareTo(b.number));

    return PrayerPlan(
      today: today,
      prayedToday: prayedToday.length,
      dailyTarget: dailyTarget,
      cyclePrayed: neighborhood.where((h) => h.isPrayed).length,
      cycleTotal: neighborhood.length,
    );
  }

  /// Starts praying through the neighborhood again. Earlier prayers stay in
  /// the lifetime totals.
  Future<void> startNewCycle(String uid) {
    return _users.updateFields(uid, {
      // Client time: the new cycle applies immediately, even offline.
      'prayerCycleStartedAt': Timestamp.now(),
    });
  }

  Future<void> togglePray(String householdId) {
    return _store.togglePray(householdId);
  }

  Future<void> updateHousehold(HouseholdModel household) {
    return _store.saveHousehold(household);
  }
}
