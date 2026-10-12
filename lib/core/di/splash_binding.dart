import 'package:get/get.dart';
import 'package:gps_cielo/features/auth/presentation/controllers/auth_controller.dart';
import 'package:gps_cielo/features/splash/domain/services/splash_service.dart';
import 'package:gps_cielo/features/splash/presentation/controllers/splash_controller.dart';

class SplashBinding extends Bindings {
  @override
  void dependencies() {
    if (!Get.isRegistered<SplashService>()) {
      Get.put<SplashService>(SplashService());
    }
    if (!Get.isRegistered<SplashController>()) {
      Get.put<SplashController>(
        SplashController(Get.find<SplashService>(), Get.find<AuthController>()),
      );
    }
  }
}
