import 'package:get/get.dart';
import 'package:gps_cielo/core/data/user_repository.dart';
import 'package:gps_cielo/core/services/household_store.dart';
import 'package:gps_cielo/core/services/location_service.dart';
import 'package:gps_cielo/features/auth/data/repositories/auth_repository.dart';
import 'package:gps_cielo/features/auth/presentation/controllers/auth_controller.dart';
import 'package:gps_cielo/features/profile/domain/services/profile_service.dart';
import 'package:gps_cielo/features/profile/presentation/controllers/profile_controller.dart';

class ProfileBinding extends Bindings {
  @override
  void dependencies() {
    if (!Get.isRegistered<ProfileService>()) {
      Get.lazyPut<ProfileService>(
        () => ProfileService(
          Get.find<UserRepository>(),
          Get.find<AuthRepository>(),
          Get.find<HouseholdStore>(),
          Get.find<LocationService>(),
        ),
      );
    }
    if (!Get.isRegistered<ProfileController>()) {
      Get.lazyPut<ProfileController>(
        () => ProfileController(
          Get.find<ProfileService>(),
          Get.find<AuthController>(),
        ),
      );
    }
  }
}
