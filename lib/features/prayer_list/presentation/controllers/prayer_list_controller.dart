import 'dart:async';

import 'package:get/get.dart';
import 'package:gps_cielo/core/models/household_model.dart';
import 'package:gps_cielo/core/models/user_model.dart';
import 'package:gps_cielo/core/utils/firebase_error_mapper.dart';
import 'package:gps_cielo/core/utils/show_snackbar.dart';
import 'package:gps_cielo/features/auth/presentation/controllers/auth_controller.dart';
import 'package:gps_cielo/features/prayer_list/domain/services/prayer_list_service.dart';

class PrayerListController extends GetxController {
  final PrayerListService _service;
  final AuthController _authController;

  PrayerListController(this._service, this._authController);

  final plan = PrayerPlan.empty.obs;
  final isLoading = false.obs;
  final isStartingCycle = false.obs;

  /// The user has a saved home (the neighborhood is built around it).
  final hasHome = false.obs;

  /// Search range from Settings, in meters.
  final rangeMeters = RxnDouble();

  /// The saved home address, for messages ("within 5 km of Demra").
  final homeLabel = 'your home'.obs;

  final List<Worker> _workers = [];

  /// Rebuilds the plan at midnight, when a new prayer day begins.
  Timer? _midnightTimer;

  /// The day an automatic new round was last tried, so a failed write
  /// (e.g. no permission) is not retried on every rebuild.
  DateTime? _autoRoundTriedOn;

  List<HouseholdModel> get todayHouseholds => plan.value.today;

  @override
  void onInit() {
    super.onInit();
    _rebuild();
    isLoading.value = _service.isLoading.value;

    _workers.addAll([
      ever(_service.neighborhood, (_) => _rebuild()),
      ever(_authController.currentUser, (_) => _rebuild()),
      ever(_service.rangeMeters, (_) => _rebuild()),
      ever(_service.isLoading, (bool loading) {
        isLoading.value = loading;
        if (!loading) _maybeStartNewRound();
      }),
    ]);
    _scheduleMidnight();
  }

  void _scheduleMidnight() {
    _midnightTimer?.cancel();
    final now = DateTime.now();
    final midnight = DateTime(now.year, now.month, now.day + 1);
    // A second late, so "today" is surely the new day.
    _midnightTimer = Timer(
      midnight.difference(now) + const Duration(seconds: 1),
      () {
        _rebuild();
        _scheduleMidnight();
      },
    );
  }

  /// Starts the next round on its own the first day after a round was
  /// finished. The day the round is finished stays a day of celebration.
  void _maybeStartNewRound() {
    if (!plan.value.needsNewRound) return;
    if (_service.isLoading.value || isStartingCycle.value) return;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    if (_autoRoundTriedOn == today) return;
    _autoRoundTriedOn = today;
    _startRound(automatic: true);
  }

  void _rebuild() {
    final UserModel? user = _authController.currentUser.value;
    hasHome.value = user?.hasLocation ?? false;
    final address = user?.address.trim() ?? '';
    homeLabel.value = address.isEmpty ? 'your home' : address;
    rangeMeters.value = _service.rangeMeters.value;
    plan.value = PrayerListService.buildPlan(
      _service.neighborhood,
      user?.dailyPrayerTarget ?? 5,
    );
    _maybeStartNewRound();
  }

  Future<void> loadTodayPrayers() => _service.refreshHouseholds();

  Future<void> togglePray(HouseholdModel household) {
    return _service.togglePray(household.id);
  }

  void updateHousehold(HouseholdModel updated) {
    _service.updateHousehold(updated);
  }

  /// Starts the next round now instead of at midnight.
  Future<void> startNewCycle() => _startRound(automatic: false);

  Future<void> _startRound({required bool automatic}) async {
    final user = _authController.currentUser.value;
    if (user == null || isStartingCycle.value) return;
    isStartingCycle.value = true;
    try {
      await _service.startNewCycle(user.id);
      SnackbarService.showSuccess(
        'A new round has begun',
        'Every neighbor is on your prayer list again.',
      );
    } catch (error) {
      // An automatic round is tried again tomorrow or on the next app start.
      if (!automatic) {
        SnackbarService.showError(
          'Could not start a new round',
          FirebaseErrorMapper.message(error),
        );
      }
    } finally {
      isStartingCycle.value = false;
    }
  }

  @override
  void onClose() {
    _midnightTimer?.cancel();
    for (final worker in _workers) {
      worker.dispose();
    }
    super.onClose();
  }
}
