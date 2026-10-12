import 'package:get/get.dart';
import 'package:gps_cielo/features/onboarding/data/repositories/onboarding_repository.dart';
import 'package:gps_cielo/features/onboarding/domain/services/onboarding_service.dart';
import 'package:gps_cielo/features/onboarding/presentation/controllers/onboarding_controller.dart';

class OnboardingBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<OnboardingRepository>(() => OnboardingRepository());
    Get.lazyPut<OnboardingService>(() => OnboardingService(Get.find<OnboardingRepository>()));
    Get.lazyPut<OnboardingController>(() => OnboardingController(Get.find<OnboardingService>()));
  }
}
