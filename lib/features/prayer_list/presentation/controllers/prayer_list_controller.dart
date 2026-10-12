import 'package:get/get.dart';
import 'package:gps_cielo/core/models/household_model.dart';
import 'package:gps_cielo/features/auth/presentation/controllers/auth_controller.dart';
import 'package:gps_cielo/features/prayer_list/domain/services/prayer_list_service.dart';

class PrayerListController extends GetxController {
  final PrayerListService _service;
  final AuthController _authController;

  PrayerListController(this._service, this._authController);

  final todayHouseholds = <HouseholdModel>[].obs;
  final cycleCompleted = 0.obs;
  final cycleTarget = 20.obs;
  final isLoading = false.obs;

  final List<Worker> _workers = [];

  int get prayedTodayCount => todayHouseholds.where((h) => h.isPrayed).length;

  @override
  void onInit() {
    super.onInit();
    _rebuild();
    isLoading.value = _service.isLoading.value;

    _workers.addAll([
      ever(_service.households, (_) => _rebuild()),
      ever(_service.totalPrayed, (_) => _rebuild()),
      ever(_authController.currentUser, (_) => _rebuild()),
      ever(_service.isLoading, (bool loading) => isLoading.value = loading),
    ]);
  }

  void _rebuild() {
    final user = _authController.currentUser.value;
    final dailyTarget = user?.dailyPrayerTarget ?? 5;

    todayHouseholds.assignAll(
      PrayerListService.buildTodayList(_service.households, dailyTarget),
    );
    cycleTarget.value = user?.prayerCycleTarget ?? 20;
    cycleCompleted.value = _service.totalPrayed.value;
  }

  Future<void> loadTodayPrayers() => _service.refreshHouseholds();

  Future<void> togglePray(HouseholdModel household) {
    return _service.togglePray(household.id);
  }

  Future<void> toggleVisited(HouseholdModel household) {
    return _service.toggleVisited(household.id);
  }

  Future<void> toggleFollowUp(HouseholdModel household) {
    return _service.toggleFollowUp(household.id);
  }

  void updateHousehold(HouseholdModel updated) {
    _service.updateHousehold(updated);
  }

  @override
  void onClose() {
    for (final worker in _workers) {
      worker.dispose();
    }
    super.onClose();
  }
}
