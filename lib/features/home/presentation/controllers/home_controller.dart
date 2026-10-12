import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:gps_cielo/core/models/household_model.dart';
import 'package:gps_cielo/core/models/user_model.dart';
import 'package:gps_cielo/core/services/address_suggestion_service.dart';
import 'package:gps_cielo/core/services/location_service.dart';
import 'package:gps_cielo/core/utils/firebase_error_mapper.dart';
import 'package:gps_cielo/core/utils/show_snackbar.dart';
import 'package:gps_cielo/features/auth/presentation/controllers/auth_controller.dart';
import 'package:gps_cielo/features/home/domain/services/home_service.dart';

class HomeController extends GetxController {
  final HomeService _homeService;
  final AuthController _authController;

  HomeController(this._homeService, this._authController);

  final searchAddressController = TextEditingController();
  final radiusHomes = 10.obs;
  final nearbyHouseholds = <HouseholdModel>[].obs;
  final isLoading = false.obs;
  final notificationCount = 0.obs;
  final nearLatitude = RxnDouble();
  final nearLongitude = RxnDouble();

  final List<Worker> _workers = [];
  StreamSubscription<int>? _unreadSubscription;
  String? _lastAppliedAddress;

  @override
  void onInit() {
    super.onInit();
    nearbyHouseholds.assignAll(_homeService.households);
    isLoading.value = _homeService.isLoading.value;
    _applyUser(_authController.currentUser.value);

    _workers.addAll([
      ever(_homeService.households, nearbyHouseholds.assignAll),
      ever(_homeService.isLoading, (bool loading) => isLoading.value = loading),
      ever(_authController.currentUser, _applyUser),
    ]);

    _unreadSubscription = _homeService.watchUnreadNotificationCount().listen(
      (count) => notificationCount.value = count,
      onError: (_) {},
    );
  }

  void _applyUser(UserModel? user) {
    if (user == null) return;
    radiusHomes.value = user.radiusHomes;
    nearLatitude.value = user.latitude;
    nearLongitude.value = user.longitude;
    if (user.address != _lastAppliedAddress) {
      _lastAppliedAddress = user.address;
      searchAddressController.text = user.address;
    }
  }

  /// Searches around the address picked from the suggestions list.
  Future<void> selectSuggestion(AddressSuggestion suggestion) {
    return searchNeighborhood(location: suggestion.toResolvedLocation());
  }

  /// Searches around the device's GPS position.
  Future<void> useCurrentLocation() async {
    isLoading.value = true;
    try {
      final location = await _homeService.currentLocation();
      searchAddressController.text = location.address;
      await searchNeighborhood(location: location);
    } catch (error) {
      SnackbarService.showError(
        'Location Unavailable',
        FirebaseErrorMapper.message(error),
      );
    } finally {
      isLoading.value = _homeService.isLoading.value;
    }
  }

  Future<void> searchNeighborhood({ResolvedLocation? location}) async {
    final address = location?.address ?? searchAddressController.text.trim();
    if (address.isEmpty) {
      SnackbarService.showError('Validation', 'Please enter an address');
      return;
    }

    final user = _authController.currentUser.value;
    if (user == null) return;

    isLoading.value = true;
    try {
      final updated = await _homeService.searchNeighborhood(
        user,
        address,
        location: location,
      );
      _lastAppliedAddress = updated.address;
      _authController.updateUser(updated);
      SnackbarService.showSuccess(
        'Search Updated',
        'Found ${nearbyHouseholds.length} nearby households',
      );
    } catch (error) {
      SnackbarService.showError(
        'Search Failed',
        FirebaseErrorMapper.message(error),
      );
    } finally {
      isLoading.value = _homeService.isLoading.value;
    }
  }

  Future<void> togglePray(HouseholdModel household) {
    return _homeService.togglePray(household.id);
  }

  void updateHousehold(HouseholdModel updated) {
    _homeService.updateHousehold(updated);
  }

  @override
  void onClose() {
    for (final worker in _workers) {
      worker.dispose();
    }
    _unreadSubscription?.cancel();
    searchAddressController.dispose();
    super.onClose();
  }
}
