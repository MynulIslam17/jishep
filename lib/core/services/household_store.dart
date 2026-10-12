import 'dart:async';

import 'package:get/get.dart';
import 'package:gps_cielo/core/data/household_repository.dart';
import 'package:gps_cielo/core/models/household_model.dart';
import 'package:gps_cielo/core/models/user_model.dart';
import 'package:gps_cielo/core/utils/firebase_error_mapper.dart';
import 'package:gps_cielo/core/utils/follow_up_date.dart';
import 'package:gps_cielo/core/utils/show_snackbar.dart';
import 'package:gps_cielo/features/notifications/data/models/notification_model.dart';
import 'package:gps_cielo/features/notifications/data/repositories/notification_repository.dart';
import 'package:gps_cielo/routes/app_routes.dart';

/// App-wide, reactive source of the signed-in user's nearby households.
///
/// Every tab (Home, Neighborhood, Prayer List, Follow Up, Profile stats) reads
/// from this store so a change made on one screen shows up everywhere. Status
/// changes are written to Firestore and flow back through a snapshot listener.
class HouseholdStore extends GetxService {
  final HouseholdRepository _repository;
  final NotificationRepository _notificationRepository;

  HouseholdStore(this._repository, this._notificationRepository);

  static const int _milestoneEvery = 10;

  /// Nearby households, nearest first, merged with the user's status.
  final households = <HouseholdModel>[].obs;
  final isLoading = false.obs;

  /// Totals across every household the user has interacted with.
  final prayedCount = 0.obs;
  final visitedCount = 0.obs;

  final Map<String, Map<String, dynamic>> _statuses = {};
  List<HouseholdSnapshot> _docs = const [];
  StreamSubscription<Map<String, Map<String, dynamic>>>? _statusSubscription;

  String? _uid;
  double? _latitude;
  double? _longitude;
  int _radiusHomes = 0;

  /// Incremented per load so a slow, outdated query cannot overwrite a newer one.
  int _loadGeneration = 0;

  /// Points the store at [user], reloading when the account, location or
  /// radius changed.
  Future<void> bindUser(UserModel user) async {
    final userChanged = user.id != _uid;
    if (userChanged) {
      clear();
      _uid = user.id;
      _statusSubscription = _repository.watchStatuses(user.id).listen(
            _onStatuses,
            onError: (Object error) => SnackbarService.showError(
              'Sync Error',
              FirebaseErrorMapper.message(error),
            ),
          );
    }

    final locationChanged = user.latitude != _latitude ||
        user.longitude != _longitude ||
        user.radiusHomes != _radiusHomes;
    if (userChanged || locationChanged) {
      _latitude = user.latitude;
      _longitude = user.longitude;
      _radiusHomes = user.radiusHomes;
      await refreshHouseholds();
    }
  }

  void clear() {
    _loadGeneration++;
    isLoading.value = false;
    _statusSubscription?.cancel();
    _statusSubscription = null;
    _uid = null;
    _latitude = null;
    _longitude = null;
    _radiusHomes = 0;
    _statuses.clear();
    _docs = const [];
    households.clear();
    prayedCount.value = 0;
    visitedCount.value = 0;
  }

  Future<void> refreshHouseholds() async {
    final latitude = _latitude;
    final longitude = _longitude;
    if (_uid == null || latitude == null || longitude == null) {
      _docs = const [];
      _rebuild();
      return;
    }

    final generation = ++_loadGeneration;
    isLoading.value = true;
    try {
      final docs = await _repository.fetchNearest(
        latitude: latitude,
        longitude: longitude,
        count: _radiusHomes,
      );
      if (generation != _loadGeneration) return;
      _docs = docs;
      _rebuild();
    } catch (error) {
      if (generation != _loadGeneration) return;
      SnackbarService.showError(
        'Could not load households',
        FirebaseErrorMapper.message(error),
      );
    } finally {
      if (generation == _loadGeneration) isLoading.value = false;
    }
  }

  HouseholdModel? findById(String id) {
    return households.firstWhereOrNull((h) => h.id == id);
  }

  Future<void> togglePray(String id) async {
    final current = findById(id);
    if (current == null) return;
    await saveHousehold(current.copyWith(isPrayed: !current.isPrayed));
  }

  Future<void> toggleVisited(String id) async {
    final current = findById(id);
    if (current == null) return;
    await saveHousehold(current.copyWith(isVisited: !current.isVisited));
  }

  Future<void> toggleFollowUp(String id) async {
    final current = findById(id);
    if (current == null) return;
    await saveHousehold(
      current.copyWith(
        hasFollowUp: !current.hasFollowUp,
        followUpDate: current.followUpDate ?? defaultFollowUpDate(),
      ),
    );
  }

  /// Persists the status fields of [updated] for the signed-in user.
  Future<void> saveHousehold(HouseholdModel updated) async {
    final uid = _uid;
    if (uid == null) return;

    final current = findById(updated.id);
    if (current != null && current.hasSameStatusAs(updated)) return;

    // Optimistic update; the snapshot listener confirms it.
    final index = households.indexWhere((h) => h.id == updated.id);
    if (index != -1) {
      households[index] = updated.copyWith(
        prayedAt: updated.isPrayed && !(current?.isPrayed ?? false)
            ? DateTime.now()
            : null,
      );
    }

    final becamePrayed = updated.isPrayed && !(current?.isPrayed ?? false);
    final becameFollowUp =
        updated.hasFollowUp && !(current?.hasFollowUp ?? false);

    try {
      final write = _repository.saveStatus(
        uid: uid,
        household: updated,
        wasPrayed: current?.isPrayed ?? false,
      );
      if (becamePrayed) _notifyMilestoneIfReached(prayedCount.value + 1);
      if (becameFollowUp) _notifyFollowUpScheduled(updated);
      await write;
    } catch (error) {
      _rebuild();
      SnackbarService.showError(
        'Could not save',
        FirebaseErrorMapper.message(error),
      );
    }
  }

  void _onStatuses(Map<String, Map<String, dynamic>> statuses) {
    _statuses
      ..clear()
      ..addAll(statuses);
    prayedCount.value =
        statuses.values.where((s) => s['isPrayed'] == true).length;
    visitedCount.value =
        statuses.values.where((s) => s['isVisited'] == true).length;
    _rebuild();
  }

  void _rebuild() {
    households.assignAll([
      for (var i = 0; i < _docs.length; i++)
        HouseholdModel.fromFirestore(
          doc: _docs[i],
          status: _statuses[_docs[i].id],
          number: i + 1,
        ),
    ]);
  }

  void _notifyMilestoneIfReached(int newCount) {
    if (newCount <= 0 || newCount % _milestoneEvery != 0) return;
    _notificationRepository
        .addNotification(
          title: 'Milestone Reached! 🎉',
          message:
              'Praise God! You have prayed for $newCount households. Keep pressing forward!',
          type: NotificationType.milestone,
          actionRoute: AppRoutes.prayerList,
        )
        .catchError((_) {});
  }

  void _notifyFollowUpScheduled(HouseholdModel household) {
    _notificationRepository
        .addNotification(
          title: 'Follow-up Scheduled',
          message:
              'Follow-up with ${household.residentName} (${household.address}) on ${household.followUpDate ?? defaultFollowUpDate()}.',
          type: NotificationType.followUpDue,
          actionRoute: AppRoutes.followUp,
        )
        .catchError((_) {});
  }

  @override
  void onClose() {
    _statusSubscription?.cancel();
    super.onClose();
  }
}
