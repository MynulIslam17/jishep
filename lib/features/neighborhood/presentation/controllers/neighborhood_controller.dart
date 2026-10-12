import 'package:get/get.dart';
import 'package:gps_cielo/core/models/household_model.dart';
import 'package:gps_cielo/core/models/user_model.dart';
import 'package:gps_cielo/features/auth/presentation/controllers/auth_controller.dart';
import 'package:gps_cielo/features/neighborhood/domain/services/neighborhood_service.dart';

enum NeighborhoodViewMode { map, list }

class NeighborhoodController extends GetxController {
  final NeighborhoodService _service;
  final AuthController _authController;

  NeighborhoodController(this._service, this._authController);

  final viewMode = NeighborhoodViewMode.map.obs;
  final households = <HouseholdModel>[].obs;
  final selectedHousehold = Rxn<HouseholdModel>();
  final radiusHomes = 10.obs;
  final isLoading = false.obs;
  final zoomLevel = 1.0.obs;

  final List<Worker> _workers = [];

  @override
  void onInit() {
    super.onInit();
    households.assignAll(_service.households);
    isLoading.value = _service.isLoading.value;
    _applyUser(_authController.currentUser.value);

    _workers.addAll([
      ever(_service.households, households.assignAll),
      ever(_service.isLoading, (bool loading) => isLoading.value = loading),
      ever(_authController.currentUser, _applyUser),
    ]);
  }

  void _applyUser(UserModel? user) {
    if (user != null) radiusHomes.value = user.radiusHomes;
  }

  Future<void> loadHouseholds() => _service.refreshHouseholds();

  void switchViewMode(NeighborhoodViewMode mode) {
    viewMode.value = mode;
  }

  void selectHousehold(HouseholdModel household) {
    selectedHousehold.value = household;
  }

  void zoomIn() {
    if (zoomLevel.value < 2.0) {
      zoomLevel.value += 0.2;
    }
  }

  void zoomOut() {
    if (zoomLevel.value > 0.6) {
      zoomLevel.value -= 0.2;
    }
  }

  Future<void> togglePray(HouseholdModel household) {
    return _service.togglePray(household.id);
  }

  Future<void> toggleVisit(HouseholdModel household) {
    return _service.toggleVisit(household.id);
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
