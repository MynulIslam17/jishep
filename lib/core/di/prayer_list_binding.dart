import 'package:get/get.dart';
import 'package:gps_cielo/core/services/household_store.dart';
import 'package:gps_cielo/features/auth/presentation/controllers/auth_controller.dart';
import 'package:gps_cielo/features/prayer_list/domain/services/prayer_list_service.dart';
import 'package:gps_cielo/features/prayer_list/presentation/controllers/prayer_list_controller.dart';

class PrayerListBinding extends Bindings {
  @override
  void dependencies() {
    if (!Get.isRegistered<PrayerListService>()) {
      Get.lazyPut<PrayerListService>(
        () => PrayerListService(Get.find<HouseholdStore>()),
      );
    }
    if (!Get.isRegistered<PrayerListController>()) {
      Get.lazyPut<PrayerListController>(
        () => PrayerListController(
          Get.find<PrayerListService>(),
          Get.find<AuthController>(),
        ),
      );
    }
  }
}
