import 'package:get/get.dart';
import 'package:gps_cielo/core/di/follow_up_binding.dart';
import 'package:gps_cielo/core/di/home_binding.dart';
import 'package:gps_cielo/core/di/neighborhood_binding.dart';
import 'package:gps_cielo/core/di/prayer_list_binding.dart';
import 'package:gps_cielo/core/di/profile_binding.dart';
import 'package:gps_cielo/features/main_nav/presentation/controllers/main_nav_controller.dart';

class MainNavBinding extends Bindings {
  @override
  void dependencies() {
    // Nav Controller
    Get.lazyPut<MainNavController>(() => MainNavController());

    // Tabs
    HomeBinding().dependencies();
    NeighborhoodBinding().dependencies();
    PrayerListBinding().dependencies();
    FollowUpBinding().dependencies();
    ProfileBinding().dependencies();
  }
}
