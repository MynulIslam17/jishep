import 'package:get/get.dart';
import 'package:gps_cielo/core/services/household_store.dart';
import 'package:gps_cielo/features/follow_up/domain/services/follow_up_service.dart';
import 'package:gps_cielo/features/follow_up/presentation/controllers/follow_up_controller.dart';

class FollowUpBinding extends Bindings {
  @override
  void dependencies() {
    if (!Get.isRegistered<FollowUpService>()) {
      Get.lazyPut<FollowUpService>(
        () => FollowUpService(Get.find<HouseholdStore>()),
      );
    }
    if (!Get.isRegistered<FollowUpController>()) {
      Get.lazyPut<FollowUpController>(
        () => FollowUpController(Get.find<FollowUpService>()),
      );
    }
  }
}
