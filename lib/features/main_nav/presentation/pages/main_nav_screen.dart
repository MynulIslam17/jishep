import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:gps_cielo/core/constants/app_colors.dart';
import 'package:gps_cielo/features/follow_up/presentation/pages/follow_up_screen.dart';
import 'package:gps_cielo/features/home/presentation/pages/home_screen.dart';
import 'package:gps_cielo/features/main_nav/presentation/controllers/main_nav_controller.dart';
import 'package:gps_cielo/features/neighborhood/presentation/pages/neighborhood_screen.dart';
import 'package:gps_cielo/features/prayer_list/presentation/pages/prayer_list_screen.dart';
import 'package:gps_cielo/features/profile/presentation/pages/profile_screen.dart';
import 'package:gps_cielo/shared/widgets/navigation/app_bottom_navigation_bar.dart';

class MainNavScreen extends GetView<MainNavController> {
  const MainNavScreen({super.key});

  static const List<Widget> _screens = [
    HomeScreen(),
    NeighborhoodScreen(),
    PrayerListScreen(),
    FollowUpScreen(),
    ProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Obx(() {
        final index = controller.currentIndex.value;
        return IndexedStack(
          index: index,
          children: List<Widget>.generate(
            _screens.length,
            (screenIndex) => controller.loadedIndices.contains(screenIndex)
                ? _screens[screenIndex]
                : const SizedBox.shrink(),
          ),
        );
      }),
      bottomNavigationBar: Obx(
        () => AppBottomNavigationBar(
          selectedDestination: controller.currentDestination,
          onDestinationSelected: controller.changeDestination,
        ),
      ),
    );
  }
}
