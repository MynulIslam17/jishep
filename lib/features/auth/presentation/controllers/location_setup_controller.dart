import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:gps_cielo/core/services/address_suggestion_service.dart';
import 'package:gps_cielo/core/services/location_service.dart';
import 'package:gps_cielo/core/utils/firebase_error_mapper.dart';
import 'package:gps_cielo/core/utils/show_snackbar.dart';
import 'package:gps_cielo/features/auth/domain/services/auth_service.dart';
import 'package:gps_cielo/features/auth/presentation/controllers/auth_controller.dart';
import 'package:gps_cielo/routes/app_routes.dart';

class LocationSetupController extends GetxController {
  final AuthService _authService;
  final AuthController _globalAuthController;
  final LocationService _locationService;

  LocationSetupController(
    this._authService,
    this._globalAuthController,
    this._locationService,
  );

  final addressController = TextEditingController();

  final addressRx = ''.obs;
  final radius = 10.0.obs;
  final isLocating = false.obs;
  final isSubmitting = false.obs;

  /// Coordinates from GPS or a picked suggestion, valid while the address
  /// text is unchanged.
  ResolvedLocation? _resolvedLocation;

  @override
  void onInit() {
    super.onInit();
    final user = _globalAuthController.currentUser.value;
    if (user != null) {
      addressController.text = user.address;
      addressRx.value = user.address;
      radius.value = user.radiusHomes.clamp(5, 25).toDouble();
    }
    addressController.addListener(() {
      addressRx.value = addressController.text;
    });
  }

  void setRadius(double val) {
    radius.value = val;
  }

  Future<void> useCurrentLocation() async {
    isLocating.value = true;
    try {
      final location = await _locationService.currentLocation();
      _resolvedLocation = location;
      addressController.text = location.address;
      addressRx.value = location.address;
    } catch (error) {
      SnackbarService.showError(
        'Location Unavailable',
        FirebaseErrorMapper.message(error),
      );
    } finally {
      isLocating.value = false;
    }
  }

  void selectSuggestion(AddressSuggestion suggestion) {
    final location = suggestion.toResolvedLocation();
    _resolvedLocation = location;
    addressRx.value = location.address;
  }

  Future<void> confirmLocation() async {
    if (isSubmitting.value) return;

    final address = addressController.text.trim();
    if (address.isEmpty) {
      SnackbarService.showError('Validation', 'Please enter your address');
      return;
    }

    isSubmitting.value = true;
    try {
      final known = _resolvedLocation;
      final location = known != null && known.address == address
          ? known
          : await _locationService.resolveAddress(address);

      await _authService.updateLocation(
        address: address,
        latitude: location.latitude,
        longitude: location.longitude,
        radiusHomes: radius.value.round(),
      );

      final currentUser = _globalAuthController.currentUser.value;
      if (currentUser != null) {
        _globalAuthController.updateUser(
          currentUser.copyWith(
            address: address,
            latitude: location.latitude,
            longitude: location.longitude,
            radiusHomes: radius.value.round(),
          ),
        );
      }

      Get.offAllNamed(AppRoutes.mainNav);
    } catch (error) {
      SnackbarService.showError(
        'Could not save location',
        FirebaseErrorMapper.message(error),
      );
    } finally {
      isSubmitting.value = false;
    }
  }

  @override
  void onClose() {
    addressController.dispose();
    super.onClose();
  }
}
