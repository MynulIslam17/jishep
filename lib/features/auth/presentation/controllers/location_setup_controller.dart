import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:gps_cielo/core/data/household_repository.dart';
import 'package:gps_cielo/core/models/household_model.dart';
import 'package:gps_cielo/core/services/address_suggestion_service.dart';
import 'package:gps_cielo/core/config/feature_flags.dart';
import 'package:gps_cielo/core/constants/app_strings.dart';
import 'package:gps_cielo/core/data/area_search.dart';
import 'package:gps_cielo/core/services/location_selection.dart';
import 'package:gps_cielo/core/services/location_service.dart';
import 'package:gps_cielo/core/utils/firebase_error_mapper.dart';
import 'package:gps_cielo/core/utils/search_range.dart';
import 'package:gps_cielo/core/utils/show_snackbar.dart';
import 'package:gps_cielo/features/auth/domain/services/auth_service.dart';
import 'package:gps_cielo/features/auth/presentation/controllers/auth_controller.dart';
import 'package:gps_cielo/routes/app_routes.dart';

/// First-run setup: the home address (the center of the user's
/// neighborhood), the search range (only when [SearchRange.userChoosesRange])
/// and the daily prayer goal. The map and count preview "my neighborhood":
/// the nearest [neighborhoodHomes] households, which the Prayer List is
/// built from.
class LocationSetupController extends GetxController {
  LocationSetupController(
    this._authService,
    this._globalAuthController,
    this._locationService,
    this._households, {
    this.previewDebounce = const Duration(milliseconds: 350),
  });

  final AuthService _authService;
  final AuthController _globalAuthController;
  final LocationService _locationService;
  final HouseholdRepository _households;
  final Duration previewDebounce;

  /// Daily prayer goals offered (same as Profile › Prayer preferences).
  static const List<int> dailyGoals = [3, 5, 10, 15];

  final addressController = TextEditingController();

  final rangeKm = SearchRange.defaultKm.obs;
  final dailyGoal = 5.obs;
  final isLocating = false.obs;
  final isSubmitting = false.obs;

  /// Why the GPS lookup failed (shown inline with a fix), or null.
  final locationError = Rxn<LocationException>();

  /// The picked location while it still matches the field.
  final selectedLocation = Rxn<ResolvedLocation>();

  /// "My neighborhood" around [selectedLocation]: the nearest
  /// [neighborhoodHomes] households (within [rangeKm] when the user picks a
  /// range), nearest first.
  final previewHouseholds = <HouseholdModel>[].obs;
  final isLoadingPreview = false.obs;
  final previewError = false.obs;

  /// No household data exists around [selectedLocation] yet (cells). Setup
  /// can still be finished.
  final previewUnavailable = false.obs;

  /// Homes in the neighborhood: the saved `radiusHomes` (new accounts are
  /// created with [SearchRange.defaultHomes]).
  int neighborhoodHomes = SearchRange.defaultHomes;

  /// The signed-in account (email, or phone for phone-only accounts).
  final accountLabel = ''.obs;

  final LocationSelection _selection = LocationSelection();
  Timer? _previewTimer;
  int _previewGeneration = 0;
  final List<Worker> _workers = [];

  bool get hasLocation => selectedLocation.value != null;

  /// e.g. "Your nearest 50 neighbors", "12 neighbors nearby"; with a range
  /// "Nearest 50 neighbors within 2 km", "40 neighbors within 2 km".
  String get previewSummary {
    if (previewError.value) return 'Could not load neighbors';
    if (previewUnavailable.value && !isLoadingPreview.value) {
      return AppStrings.areaUnavailable;
    }
    final n = previewHouseholds.length;
    final noun = n == 1 ? 'neighbor' : 'neighbors';
    final full = n >= neighborhoodHomes;
    if (!SearchRange.userChoosesRange) {
      if (isLoadingPreview.value) return 'Finding your nearest neighbors…';
      if (n == 0) return 'No households near this address yet';
      return full ? 'Your nearest $n $noun' : '$n $noun nearby';
    }
    final range = SearchRange.formatKm(rangeKm.value);
    if (isLoadingPreview.value) return 'Finding neighbors within $range…';
    if (n == 0) return 'No households within $range yet';
    return full ? 'Nearest $n $noun within $range' : '$n $noun within $range';
  }

  /// Meters from the picked home to [household], or null.
  double? distanceTo(HouseholdModel household) {
    final home = selectedLocation.value;
    if (home == null) return null;
    return SearchRange.distanceMeters(
      home.latitude,
      home.longitude,
      household.latitude,
      household.longitude,
    );
  }

  /// Days to pray once for every household in the neighborhood at the
  /// daily goal (one round).
  int? get cycleDays {
    final n = previewHouseholds.length;
    if (n == 0 || dailyGoal.value <= 0) return null;
    return (n / dailyGoal.value).ceil();
  }

  @override
  void onInit() {
    super.onInit();
    final user = _globalAuthController.currentUser.value;
    if (user != null) {
      accountLabel.value = user.email.isNotEmpty
          ? user.email
          : (user.phone ?? '');
      rangeKm.value = SearchRange.normalizeKm(user.searchRadiusKm);
      neighborhoodHomes = user.radiusHomes;
      dailyGoal.value = dailyGoals.contains(user.dailyPrayerTarget)
          ? user.dailyPrayerTarget
          : 5;
      // Coming back to setup: start from what is already saved.
      final lat = user.latitude;
      final lng = user.longitude;
      if (lat != null && lng != null && user.address.trim().isNotEmpty) {
        final saved = ResolvedLocation(
          address: user.address,
          latitude: lat,
          longitude: lng,
          source: LocationSource.search,
        );
        addressController.text = saved.address;
        _selection.pick(saved);
        selectedLocation.value = saved;
      } else {
        addressController.text = user.address;
      }
    }

    addressController.addListener(() {
      if (!_selection.appliesTo(addressController.text)) {
        _selection.clear();
        selectedLocation.value = null;
      }
    });
    _workers.addAll([
      ever(selectedLocation, (_) => _schedulePreview()),
      ever(rangeKm, (_) => _schedulePreview()),
    ]);
    _schedulePreview();
  }

  void setRange(double km) => rangeKm.value = km;

  void setDailyGoal(int goal) => dailyGoal.value = goal;

  /// Fills the field from the device GPS. Nothing is saved until the user
  /// confirms.
  Future<void> useCurrentLocation() async {
    if (isLocating.value) return;
    isLocating.value = true;
    locationError.value = null;
    try {
      final location = await _locationService.currentLocation();
      _selection.pick(location);
      addressController.text = location.address;
      selectedLocation.value = location;
    } on LocationException catch (error) {
      locationError.value = error;
    } catch (error) {
      SnackbarService.showError(
        'Location Unavailable',
        FirebaseErrorMapper.message(error),
      );
    } finally {
      isLocating.value = false;
    }
  }

  /// Opens the system screen that fixes [locationError].
  Future<void> openLocationSettings() async {
    final error = locationError.value;
    if (error == null) return;
    await _locationService.openSettingsFor(error.reason);
  }

  void selectSuggestion(AddressSuggestion suggestion) {
    final location = suggestion.toResolvedLocation();
    _selection.pick(location);
    locationError.value = null;
    selectedLocation.value = location;
  }

  void retryPreview() => _schedulePreview(immediate: true);

  void _schedulePreview({bool immediate = false}) {
    _previewTimer?.cancel();
    final location = selectedLocation.value;
    final generation = ++_previewGeneration;
    previewUnavailable.value = false;
    if (location == null) {
      previewHouseholds.clear();
      isLoadingPreview.value = false;
      previewError.value = false;
      return;
    }
    isLoadingPreview.value = true;
    previewError.value = false;
    _previewTimer = Timer(
      immediate ? Duration.zero : previewDebounce,
      () => _loadPreview(location, rangeKm.value, generation),
    );
  }

  Future<void> _loadPreview(
    ResolvedLocation location,
    double km,
    int generation,
  ) async {
    try {
      // Nearest first, reading only as far as the neighborhood needs.
      final AreaSearch search = FeatureFlags.useCellHouseholds
          ? _households.cellArea(
              latitude: location.latitude,
              longitude: location.longitude,
            )
          : GeoSearchArea(
              _households.geoSearch(
                latitude: location.latitude,
                longitude: location.longitude,
                radiusKm: km,
              ),
            );
      await search.ensure(neighborhoodHomes);
      if (generation != _previewGeneration) return;
      previewUnavailable.value = search.isUnavailable;
      final records = search.records.take(neighborhoodHomes).toList();
      previewHouseholds.assignAll([
        for (var i = 0; i < records.length; i++)
          HouseholdModel.fromRecord(record: records[i], number: i + 1),
      ]);
    } catch (_) {
      if (generation != _previewGeneration) return;
      previewHouseholds.clear();
      previewError.value = true;
    } finally {
      if (generation == _previewGeneration) isLoadingPreview.value = false;
    }
  }

  Future<void> signOut() => _globalAuthController.signOut();

  Future<void> confirmLocation() async {
    if (isSubmitting.value) return;

    final address = addressController.text.trim();
    if (address.isEmpty && selectedLocation.value == null) {
      SnackbarService.showError(
        'Home address',
        'Search for your address or use your current location.',
      );
      return;
    }

    isSubmitting.value = true;
    try {
      final location =
          _selection.locationFor(address) ??
          await _locationService.resolveAddress(address);
      final label = location.hasAddress
          ? location.address
          : location.coordinatesLabel;

      await _authService.updateLocation(
        address: label,
        latitude: location.latitude,
        longitude: location.longitude,
        searchRadiusKm: rangeKm.value,
        dailyPrayerTarget: dailyGoal.value,
      );

      final currentUser = _globalAuthController.currentUser.value;
      if (currentUser != null) {
        _globalAuthController.updateUser(
          currentUser.copyWith(
            address: label,
            latitude: location.latitude,
            longitude: location.longitude,
            searchRadiusKm: rangeKm.value,
            dailyPrayerTarget: dailyGoal.value,
          ),
        );
      }

      Get.offAllNamed(AppRoutes.mainNav);
    } catch (error) {
      SnackbarService.showError(
        'Could not save your home',
        FirebaseErrorMapper.message(error),
      );
    } finally {
      isSubmitting.value = false;
    }
  }

  @override
  void onClose() {
    _previewTimer?.cancel();
    for (final w in _workers) {
      w.dispose();
    }
    addressController.dispose();
    super.onClose();
  }
}
