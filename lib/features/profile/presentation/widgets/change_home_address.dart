import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:gps_cielo/features/main_nav/presentation/controllers/main_nav_controller.dart';
import 'package:gps_cielo/features/main_nav/presentation/models/main_nav_destination.dart';
import 'package:gps_cielo/features/profile/presentation/controllers/profile_controller.dart';
import 'package:gps_cielo/features/profile/presentation/widgets/profile_address_bottom_sheet.dart';

/// Opens the same "My address" sheet as Profile, from anywhere in the main
/// tabs (e.g. "This area isn't available yet" → Change home address).
abstract final class ChangeHomeAddress {
  static const String label = 'Change home address';

  /// A button for "area not available" states.
  static Widget button({Key? key}) => OutlinedButton.icon(
    key: key ?? const ValueKey('change-home-address'),
    onPressed: () => open(Get.context!),
    icon: const Icon(Icons.home_outlined, size: 16),
    label: const Text(label),
  );

  static void open(BuildContext context) {
    if (!Get.isRegistered<ProfileController>()) {
      // Not in the main tabs: Profile has the same item.
      if (Get.isRegistered<MainNavController>()) {
        Get.find<MainNavController>().changeDestination(
          MainNavDestination.profile,
        );
      }
      return;
    }
    final controller = Get.find<ProfileController>();
    final user = controller.user.value;
    ProfileAddressBottomSheet.show(
      context,
      currentAddress: user?.address ?? '',
      nearLatitude: user?.latitude,
      nearLongitude: user?.longitude,
      onSaveAddress: (newAddr, location) =>
          controller.updateAddress(newAddr, location: location),
      onUseCurrentLocation: controller.locateDevice,
    );
  }
}
