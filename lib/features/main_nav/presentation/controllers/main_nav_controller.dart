import 'package:get/get.dart';
import 'package:gps_cielo/features/main_nav/presentation/models/main_nav_destination.dart';

class MainNavController extends GetxController {
  final currentIndex = 0.obs;
  final loadedIndices = <int>{0}.obs;

  MainNavDestination get currentDestination =>
      MainNavDestination.values[currentIndex.value];

  void changeDestination(MainNavDestination destination) {
    final index = destination.index;
    currentIndex.value = index;
    loadedIndices.add(index);
  }
}
