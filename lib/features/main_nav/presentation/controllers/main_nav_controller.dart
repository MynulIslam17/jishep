import 'package:get/get.dart';
import 'package:gps_cielo/core/services/push/push_notification_service.dart';
import 'package:gps_cielo/features/main_nav/presentation/models/main_nav_destination.dart';

class MainNavController extends GetxController {
  final currentIndex = 0.obs;
  final loadedIndices = <int>{0}.obs;

  @override
  void onReady() {
    super.onReady();
    // The main app is on screen: notifications may ask for permission and
    // open a tapped notification now.
    if (Get.isRegistered<PushNotificationService>()) {
      Get.find<PushNotificationService>().onAppReady();
    }
  }

  MainNavDestination get currentDestination =>
      MainNavDestination.values[currentIndex.value];

  void changeDestination(MainNavDestination destination) {
    final index = destination.index;
    currentIndex.value = index;
    loadedIndices.add(index);
  }
}
