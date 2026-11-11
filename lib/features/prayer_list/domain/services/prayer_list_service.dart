import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:get/get.dart';
import 'package:gps_cielo/core/data/user_repository.dart';
import 'package:gps_cielo/core/models/household_model.dart';
import 'package:gps_cielo/core/services/household_store.dart';

/// Today's prayers and the prayer round ("cycle" in data), worked out from
/// "my neighborhood": the Settings number of households within the Settings
/// range around the saved home ([HouseholdStore.homeHouseholds]).
///
/// A day runs from midnight to midnight on the phone. Each day lists the
/// nearest households not yet prayed for in this round, up to the daily goal.
/// When every neighbor has been prayed for, a new round starts on its own at
/// the next midnight ([needsNewRound]).
class PrayerPlan {
  /// Today's households: those already prayed for today, then the nearest
  /// not yet prayed for in this round, up to the daily goal.
  final List<HouseholdModel> today;

  /// Households prayed for today, extras included.
  final int prayedToday;

  /// The daily goal from Settings.
  final int dailyTarget;

  /// Today's goal: the daily goal, or fewer when fewer neighbors are left in
  /// this round. Extra prayers never raise it.
  final int todayGoal;

  /// Households in the neighborhood prayed for in this round / all of them.
  final int cyclePrayed;
  final int cycleTotal;

  const PrayerPlan({
    required this.today,
    required this.prayedToday,
    required this.dailyTarget,
    required this.todayGoal,
    required this.cyclePrayed,
    required this.cycleTotal,
  });

  static const empty = PrayerPlan(
    today: [],
    prayedToday: 0,
    dailyTarget: 0,
    todayGoal: 0,
    cyclePrayed: 0,
    cycleTotal: 0,
  );

  int get cycleRemaining => cycleTotal - cyclePrayed;

  /// Prayed for today, counted toward today's goal (at most the goal).
  int get countedToday => math.min(prayedToday, todayGoal);

  /// Prayers today beyond today's goal.
  int get extraToday => math.max(0, prayedToday - todayGoal);

  /// Households still to pray for to reach today's goal.
  int get leftToday => todayGoal - countedToday;

  /// Every household in the neighborhood has been prayed for this round.
  bool get isCycleComplete => cycleTotal > 0 && cyclePrayed >= cycleTotal;

  /// Today's goal is reached.
  bool get isTodayDone => todayGoal > 0 && prayedToday >= todayGoal;

  /// Households on tomorrow's list, if today's goal is reached.
  int get tomorrowCount => math.min(dailyTarget, cycleRemaining);

  /// Tomorrow's list holds the last neighbors of this round.
  bool get tomorrowIsLast =>
      cycleRemaining > 0 && cycleRemaining <= dailyTarget;

  /// The daily goal is more than the whole neighborhood (Settings "Households
  /// to show"), so the goal can never be met as set.
  bool get goalAboveNeighborhood => cycleTotal > 0 && dailyTarget > cycleTotal;

  /// The round was finished on an earlier day: time for a new round.
  bool get needsNewRound => isCycleComplete && prayedToday == 0;

  /// Days left in the round at the daily goal (today included).
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
    final todayGoal = math.min(
      math.max(0, dailyTarget),
      prayedToday.length + notYet.length,
    );
    final today = [...prayedToday, ...notYet.take(slots)]
      ..sort((a, b) => a.number.compareTo(b.number));

    return PrayerPlan(
      today: today,
      prayedToday: prayedToday.length,
      dailyTarget: dailyTarget,
      todayGoal: todayGoal,
      cyclePrayed: neighborhood.where((h) => h.isPrayed).length,
      cycleTotal: neighborhood.length,
    );
  }

  /// Starts a new round: every neighbor can be prayed for again. Earlier
  /// prayers stay in the lifetime totals; visits, invitations, follow-ups and
  /// notes are not touched.
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
