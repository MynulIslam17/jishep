import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:gps_cielo/core/models/household_model.dart';
import 'package:gps_cielo/core/models/user_model.dart';
import 'package:gps_cielo/core/services/address_suggestion_service.dart';
import 'package:gps_cielo/core/services/home_address_service.dart';
import 'package:gps_cielo/core/services/household_store.dart';
import 'package:gps_cielo/core/services/location_service.dart';
import 'package:gps_cielo/core/utils/firebase_error_mapper.dart';
import 'package:gps_cielo/core/utils/search_range.dart';
import 'package:gps_cielo/core/utils/show_snackbar.dart';
import 'package:gps_cielo/features/auth/presentation/controllers/auth_controller.dart';
import 'package:gps_cielo/features/home/domain/services/home_service.dart';

class HomeController extends GetxController {
  final HomeService _homeService;
  final AuthController _authController;
  final HomeAddressService _homeAddress;

  HomeController(this._homeService, this._authController, this._homeAddress);

  /// True while "Set as my home" saves.
  final isSavingHome = false.obs;

  /// The searched place, kept so it can be saved as the home address.
  ResolvedLocation? _searchedLocation;

  final searchAddressController = TextEditingController();

  /// How many nearest homes are shown (the Home filter or the default).
  static const List<int> radiusOptions = SearchRange.options;
  final radiusHomes = SearchRange.defaultHomes.obs;

  /// Default number of households (Settings > My preferences).
  final defaultRadius = SearchRange.defaultHomes.obs;

  /// True while the Home filter differs from the default.
  final isRadiusFiltered = false.obs;

  /// True while the "Search my neighborhood" request runs.
  final isSearching = false.obs;

  /// True while waiting for a GPS fix.
  final isLocating = false.obs;

  /// The search range from Settings, in meters.
  final rangeMeters = RxnDouble();

  /// Label of the current search center (home address or searched place).
  final centerLabel = ''.obs;
  final nearbyHouseholds = <HouseholdModel>[].obs;

  /// Every household within the range (the slider shows the nearest few).
  final foundInRange = 0.obs;
  final areaComplete = false.obs;
  final isLoading = false.obs;
  final notificationCount = 0.obs;

  /// Saved home location; biases address suggestions.
  final nearLatitude = RxnDouble();
  final nearLongitude = RxnDouble();

  /// Where households are currently searched around (map center).
  final centerLatitude = RxnDouble();
  final centerLongitude = RxnDouble();

  /// True while showing results for a searched place instead of home.
  final isTemporarySearch = false.obs;

  /// False until the user has a home location or has searched a place.
  final hasSearchCenter = false.obs;

  final List<Worker> _workers = [];
  StreamSubscription<int>? _unreadSubscription;
  String? _lastAppliedAddress;

  @override
  void onInit() {
    super.onInit();
    nearbyHouseholds.assignAll(_homeService.households);
    foundInRange.value = _homeService.foundInRange.value;
    areaComplete.value = _homeService.areaComplete.value;
    rangeMeters.value = _homeService.rangeMeters.value;
    _applyRadius();
    isLoading.value = _homeService.isLoading.value;
    // Center first: a temporary search may already be active when this
    // controller is (re)created, and the field must show that place.
    _applyCenter(_homeService.center.value);
    _applyUser(_authController.currentUser.value);
    final center = _homeService.center.value;
    if (center != null && center.isTemporary) {
      searchAddressController.text = center.label;
    }

    _workers.addAll([
      ever(_homeService.center, _applyCenter),
      ever(_homeService.rangeMeters, (double? m) => rangeMeters.value = m),
      ever(_homeService.activeRadius, (_) => _applyRadius()),
      ever(_homeService.isRadiusFiltered, (_) => _applyRadius()),
      ever(_homeService.defaultHomes, (_) => _applyRadius()),
      ever(_homeService.households, nearbyHouseholds.assignAll),
      ever(_homeService.foundInRange, (int n) => foundInRange.value = n),
      ever(_homeService.areaComplete, (bool c) => areaComplete.value = c),
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
    nearLatitude.value = user.latitude;
    nearLongitude.value = user.longitude;
    if (isTemporarySearch.value) return;
    if (user.address != _lastAppliedAddress) {
      _lastAppliedAddress = user.address;
      searchAddressController.text = user.address;
    }
  }

  void _applyRadius() {
    final active = _homeService.activeRadius.value;
    if (active > 0) radiusHomes.value = active;
    final defaults = _homeService.defaultHomes.value;
    if (defaults > 0) defaultRadius.value = defaults;
    isRadiusFiltered.value = _homeService.isRadiusFiltered.value;
  }

  void _applyCenter(SearchCenter? center) {
    centerLatitude.value = center?.latitude;
    centerLongitude.value = center?.longitude;
    isTemporarySearch.value = center?.isTemporary ?? false;
    hasSearchCenter.value = center != null;
    centerLabel.value = center?.label ?? '';
  }

  /// Filters Home to the [homes] nearest households. Not saved.
  Future<void> changeRadius(int homes) async {
    if (homes == radiusHomes.value) return;
    radiusHomes.value = homes;
    await _homeService.filterRadius(homes);
  }

  /// Back to the default range from Settings.
  Future<void> resetRadius() => _homeService.filterRadius(null);

  bool _isSavedAddress(String text) {
    final saved = _authController.currentUser.value?.address.trim() ?? '';
    return saved.isNotEmpty && text.trim().toLowerCase() == saved.toLowerCase();
  }

  /// Searches around the address picked from the suggestions list.
  Future<void> selectSuggestion(AddressSuggestion suggestion) {
    return searchNeighborhood(location: suggestion.toResolvedLocation());
  }

  /// Searches around the device's GPS position (not saved to the profile).
  Future<void> useCurrentLocation() async {
    if (isLocating.value || isSearching.value) return;
    isLocating.value = true;
    try {
      final location = await _homeService.currentLocation();
      searchAddressController.text = location.hasAddress
          ? location.address
          : location.coordinatesLabel;
      await searchNeighborhood(location: location);
    } catch (error) {
      SnackbarService.showError(
        'Location Unavailable',
        FirebaseErrorMapper.message(error),
      );
    } finally {
      isLocating.value = false;
    }
  }

  /// Temporary search around an address. The saved home address is kept.
  Future<void> searchNeighborhood({ResolvedLocation? location}) async {
    if (isSearching.value || (location == null && isLocating.value)) return;
    final address = location?.address ?? searchAddressController.text.trim();
    if (address.isEmpty && location == null) {
      SnackbarService.showError('Validation', 'Please enter an address');
      return;
    }
    final user = _authController.currentUser.value;
    if (user == null) return;

    isSearching.value = true;
    try {
      // Searching the saved home address simply shows home again.
      if (location == null && user.hasLocation && _isSavedAddress(address)) {
        await useHomeAddress();
        return;
      }

      isLoading.value = true;
      _searchedLocation = await _homeService.searchNeighborhood(
        address,
        location: location,
      );
      final found = _homeService.households.length;
      SnackbarService.showSuccess(
        'Search Updated',
        found == 0
            ? 'No households found near this location yet'
            : 'Found $found nearby households',
      );
    } catch (error) {
      SnackbarService.showError(
        'Search Failed',
        FirebaseErrorMapper.message(error),
      );
    } finally {
      isSearching.value = false;
      isLoading.value = _homeService.isLoading.value;
    }
  }

  /// Returns to the households around the saved home address.
  Future<void> useHomeAddress() async {
    _searchedLocation = null;
    if (_homeService.center.value?.isTemporary ?? false) {
      await _homeService.useSavedLocation();
    } else {
      await _homeService.refreshHouseholds();
    }
    final user = _authController.currentUser.value;
    _lastAppliedAddress = user?.address;
    searchAddressController.text = user?.address ?? '';
  }

  /// Saves the searched place as the home address (after the user
  /// confirmed). Prayer List, Neighborhood and Home then use it.
  Future<void> setSearchedPlaceAsHome() async {
    final user = _authController.currentUser.value;
    final center = _homeService.center.value;
    if (user == null || center == null || !center.isTemporary) return;
    if (isSavingHome.value) return;
    final location =
        _searchedLocation ??
        ResolvedLocation(
          address: center.label,
          latitude: center.latitude,
          longitude: center.longitude,
        );
    isSavingHome.value = true;
    try {
      final updated = await _homeAddress.save(user, location);
      _authController.updateUser(updated);
      _searchedLocation = null;
      _lastAppliedAddress = updated.address;
      searchAddressController.text = updated.address;
      SnackbarService.showSuccess(
        'Home Address Updated',
        'Your Prayer List now uses households near ${updated.address}.',
      );
    } catch (error) {
      SnackbarService.showError(
        'Address Not Saved',
        FirebaseErrorMapper.message(error),
      );
    } finally {
      isSavingHome.value = false;
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
