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
      ever(_service.isLoading, (bool loading) => isLoading.value = loading),
    ]);
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
  }

  Future<void> loadTodayPrayers() => _service.refreshHouseholds();

  Future<void> togglePray(HouseholdModel household) {
    return _service.togglePray(household.id);
  }

  void updateHousehold(HouseholdModel updated) {
    _service.updateHousehold(updated);
  }

  /// Begins praying through the whole neighborhood again.
  Future<void> startNewCycle() async {
    final user = _authController.currentUser.value;
    if (user == null || isStartingCycle.value) return;
    isStartingCycle.value = true;
    try {
      await _service.startNewCycle(user.id);
      SnackbarService.showSuccess(
        'New Prayer Cycle',
        'Your neighborhood is ready to be prayed for again.',
      );
    } catch (error) {
      SnackbarService.showError(
        'Could not start a new cycle',
        FirebaseErrorMapper.message(error),
      );
    } finally {
      isStartingCycle.value = false;
    }
  }

  @override
  void onClose() {
    for (final worker in _workers) {
      worker.dispose();
    }
    super.onClose();
  }
}
