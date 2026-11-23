import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:gps_cielo/core/constants/app_strings.dart';
import 'package:gps_cielo/core/models/household_model.dart';
import 'package:gps_cielo/core/services/address_suggestion_service.dart';
import 'package:gps_cielo/core/services/home_address_service.dart';
import 'package:gps_cielo/core/services/household_store.dart';
import 'package:gps_cielo/core/services/location_service.dart';
import 'package:gps_cielo/core/utils/firebase_error_mapper.dart';
import 'package:gps_cielo/core/utils/show_snackbar.dart';
import 'package:gps_cielo/features/auth/presentation/controllers/auth_controller.dart';
import 'package:gps_cielo/features/neighborhood/domain/services/neighborhood_service.dart';
import 'package:gps_cielo/shared/widgets/map/household_osm_map.dart';

enum NeighborhoodViewMode { map, list }

/// Neighborhood tab (Figma "My Neighborhood"): the nearest N homes on a map
/// or in a list. The header search looks around another place for a while
/// (never saved unless the user picks "Set as my home").
class NeighborhoodController extends GetxController {
  final NeighborhoodService _service;
  final AuthController? _auth;
  final HomeAddressService? _homeAddress;

  NeighborhoodController(
    this._service, {
    AuthController? auth,
    HomeAddressService? homeAddress,
  }) : _auth = auth,
       _homeAddress = homeAddress;

  final viewMode = NeighborhoodViewMode.map.obs;

  /// The nearest N homes around the center: pins and rows.
  final households = <HouseholdModel>[].obs;

  /// No household data exists around the current center (cells).
  final areaUnavailable = false.obs;

  /// Where the homes came from (Melissa-first), or null.
  final areaSourceNote = RxnString();
  final isLoading = false.obs;

  /// True while showing a searched place instead of the saved home.
  final isTemporary = false.obs;

  /// The center's label: the home address or the searched place.
  final centerLabel = ''.obs;
  final centerLatitude = RxnDouble();
  final centerLongitude = RxnDouble();

  /// Zooms the map from the +/- buttons.
  final mapHandle = HouseholdMapHandle();

  // Search ("look around another place").
  final searchController = TextEditingController();
  final isSearching = false.obs;
  final isLocating = false.obs;
  final isSavingHome = false.obs;

  /// The searched place, kept so it can be saved as the home address.
  ResolvedLocation? _searchedLocation;

  final List<Worker> _workers = [];

  int get prayedCount => households.where((h) => h.isPrayed).length;
  int get toPrayCount => households.length - prayedCount;

  /// The saved home, which biases address suggestions.
  double? get homeLatitude => _auth?.currentUser.value?.latitude;
  double? get homeLongitude => _auth?.currentUser.value?.longitude;

  @override
  void onInit() {
    super.onInit();
    households.assignAll(_service.households);
    areaUnavailable.value = _service.areaUnavailable.value;
    areaSourceNote.value = _service.areaSourceNote.value;
    isLoading.value = _service.isLoading.value;
    _applyCenter(_service.center.value);

    _workers.addAll([
      ever(_service.center, _applyCenter),
      ever(_service.households, households.assignAll),
      ever(_service.areaUnavailable, (bool u) => areaUnavailable.value = u),
      ever(_service.areaSourceNote, (String? n) => areaSourceNote.value = n),
      ever(_service.isLoading, (bool loading) => isLoading.value = loading),
    ]);
  }

  void _applyCenter(SearchCenter? center) {
    centerLatitude.value = center?.latitude;
    centerLongitude.value = center?.longitude;
    isTemporary.value = center?.isTemporary ?? false;
    centerLabel.value = center?.label ?? '';
  }

  Future<void> loadHouseholds() => _service.refreshHouseholds();

  void switchViewMode(NeighborhoodViewMode mode) => viewMode.value = mode;

  Future<void> zoomIn() => mapHandle.zoomIn();

  Future<void> zoomOut() => mapHandle.zoomOut();

  Future<void> togglePray(HouseholdModel household) {
    return _service.togglePray(household.id);
  }

  void updateHousehold(HouseholdModel updated) {
    _service.updateHousehold(updated);
  }

  /// Looks around the address picked from the suggestions list.
  Future<void> selectSuggestion(AddressSuggestion suggestion) {
    return searchNeighborhood(location: suggestion.toResolvedLocation());
  }

  /// Looks around the device's GPS position (not saved to the profile).
  Future<void> useCurrentLocation() async {
    if (isLocating.value || isSearching.value) return;
    isLocating.value = true;
    try {
      final location = await _service.currentLocation();
      searchController.text = location.hasAddress
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

  bool _isSavedAddress(String text) {
    final saved = _auth?.currentUser.value?.address.trim() ?? '';
    return saved.isNotEmpty && text.trim().toLowerCase() == saved.toLowerCase();
  }

  /// Temporary search around an address. The saved home address is kept.
  Future<void> searchNeighborhood({ResolvedLocation? location}) async {
    if (isSearching.value || (location == null && isLocating.value)) return;
    final address = location?.address ?? searchController.text.trim();
    if (address.isEmpty && location == null) {
      SnackbarService.showError('Validation', 'Please enter an address');
      return;
    }
    isSearching.value = true;
    try {
      // Searching the saved home address simply shows home again.
      if (location == null && _isSavedAddress(address)) {
        await useHomeAddress();
        return;
      }
      _searchedLocation = await _service.searchNeighborhood(
        address,
        location: location,
      );
      final found = _service.households.length;
      SnackbarService.showSuccess(
        'Looking around',
        found == 0
            ? (_service.areaUnavailable.value
                  ? AppStrings.areaUnavailable
                  : 'No households found near this place yet')
            : 'The nearest $found homes to this place',
      );
    } catch (error) {
      SnackbarService.showError(
        'Search Failed',
        FirebaseErrorMapper.message(error),
      );
    } finally {
      isSearching.value = false;
    }
  }

  /// Back to the homes around the saved home address.
  Future<void> useHomeAddress() async {
    _searchedLocation = null;
    searchController.clear();
    if (_service.center.value?.isTemporary ?? false) {
      await _service.useSavedLocation();
    } else {
      await _service.refreshHouseholds();
    }
  }

  /// Saves the searched place as the home address (after the user
  /// confirmed). Prayer List, Neighborhood and Home then use it.
  Future<void> setSearchedPlaceAsHome() async {
    final auth = _auth;
    final homeAddress = _homeAddress;
    final user = auth?.currentUser.value;
    final center = _service.center.value;
    if (auth == null || homeAddress == null || user == null) return;
    if (center == null || !center.isTemporary || isSavingHome.value) return;
    final location =
        _searchedLocation ??
        ResolvedLocation(
          address: center.label,
          latitude: center.latitude,
          longitude: center.longitude,
        );
    isSavingHome.value = true;
    try {
      final updated = await homeAddress.save(user, location);
      auth.updateUser(updated);
      _searchedLocation = null;
      searchController.clear();
      SnackbarService.showSuccess(
        'Home Address Updated',
        'Your neighbors are now the homes nearest ${updated.address}.',
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

  @override
  void onClose() {
    for (final worker in _workers) {
      worker.dispose();
    }
    searchController.dispose();
    super.onClose();
  }
}
