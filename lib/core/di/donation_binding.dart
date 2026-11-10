import 'package:get/get.dart';
import 'package:gps_cielo/features/auth/presentation/controllers/auth_controller.dart';
import 'package:gps_cielo/features/donation/domain/services/donation_service.dart';
import 'package:gps_cielo/features/donation/presentation/controllers/donation_controller.dart';

class DonationBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<DonationService>(DonationService.new, fenix: true);
    Get.lazyPut<DonationController>(
      () => DonationController(
        Get.find<DonationService>(),
        Get.find<AuthController>(),
      ),
    );
  }
}
