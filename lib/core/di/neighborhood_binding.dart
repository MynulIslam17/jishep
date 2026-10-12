import 'package:get/get.dart';
import 'package:gps_cielo/core/services/household_store.dart';
import 'package:gps_cielo/features/auth/presentation/controllers/auth_controller.dart';
import 'package:gps_cielo/features/neighborhood/domain/services/neighborhood_service.dart';
import 'package:gps_cielo/features/neighborhood/presentation/controllers/neighborhood_controller.dart';

class NeighborhoodBinding extends Bindings {
  @override
  void dependencies() {
    if (!Get.isRegistered<NeighborhoodService>()) {
      Get.lazyPut<NeighborhoodService>(
        () => NeighborhoodService(Get.find<HouseholdStore>()),
      );
    }
    if (!Get.isRegistered<NeighborhoodController>()) {
      Get.lazyPut<NeighborhoodController>(
        () => NeighborhoodController(
          Get.find<NeighborhoodService>(),
          Get.find<AuthController>(),
        ),
      );
    }
  }
}
