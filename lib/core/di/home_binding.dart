import 'package:get/get.dart';
import 'package:gps_cielo/core/data/user_repository.dart';
import 'package:gps_cielo/core/services/household_store.dart';
import 'package:gps_cielo/core/services/location_service.dart';
import 'package:gps_cielo/features/auth/presentation/controllers/auth_controller.dart';
import 'package:gps_cielo/features/home/domain/services/home_service.dart';
import 'package:gps_cielo/features/home/presentation/controllers/home_controller.dart';
import 'package:gps_cielo/features/notifications/data/repositories/notification_repository.dart';

class HomeBinding extends Bindings {
  @override
  void dependencies() {
    if (!Get.isRegistered<HomeService>()) {
      Get.lazyPut<HomeService>(
        () => HomeService(
          Get.find<HouseholdStore>(),
          Get.find<LocationService>(),
          Get.find<UserRepository>(),
          Get.find<NotificationRepository>(),
        ),
      );
    }
    if (!Get.isRegistered<HomeController>()) {
      Get.lazyPut<HomeController>(
        () => HomeController(
          Get.find<HomeService>(),
          Get.find<AuthController>(),
        ),
      );
    }
  }
}
