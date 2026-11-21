import 'dart:async';

import 'package:get/get.dart';
import 'package:gps_cielo/core/models/household_model.dart';
import 'package:gps_cielo/core/models/user_model.dart';
import 'package:gps_cielo/features/auth/presentation/controllers/auth_controller.dart';
import 'package:gps_cielo/features/home/domain/services/home_service.dart';
import 'package:gps_cielo/features/prayer_list/domain/services/prayer_list_service.dart';

/// Home (Figma "Home"): a greeting, today's neighbors, a small map of the
/// neighborhood and today's homes to pray for. Always the saved home's
/// neighborhood; looking around another place is on the Neighborhood tab.
class HomeController extends GetxController {
  final HomeService _homeService;
  final AuthController _authController;

  HomeController(this._homeService, this._authController);

  /// Today's prayers and the round, as on the Prayer List.
  final plan = PrayerPlan.empty.obs;

  /// "My neighborhood": the nearest N homes around the saved home.
  final neighborhood = <HouseholdModel>[].obs;

  final hasHome = false.obs;

  /// No household data exists around the saved home (cells).
  final homeUnavailable = false.obs;
  final isLoading = false.obs;
  final notificationCount = 0.obs;

  /// "Maria" from the profile's full name ('' when unknown).
  final firstName = ''.obs;

  /// The saved home, for the map center and distances.
  final homeLatitude = RxnDouble();
  final homeLongitude = RxnDouble();

  final List<Worker> _workers = [];
  StreamSubscription<int>? _unreadSubscription;

  @override
  void onInit() {
    super.onInit();
    _rebuild();
    isLoading.value = _homeService.isLoading.value;
    homeUnavailable.value = _homeService.homeUnavailable.value;

    _workers.addAll([
      ever(_homeService.neighborhood, (_) => _rebuild()),
      ever(_authController.currentUser, (_) => _rebuild()),
      ever(_homeService.isLoading, (bool loading) => isLoading.value = loading),
      ever(
        _homeService.homeUnavailable,
        (bool unavailable) => homeUnavailable.value = unavailable,
      ),
    ]);

    _unreadSubscription = _homeService.watchUnreadNotificationCount().listen(
      (count) => notificationCount.value = count,
      onError: (_) {},
    );
  }

  void _rebuild() {
    final UserModel? user = _authController.currentUser.value;
    hasHome.value = user?.hasLocation ?? false;
    homeLatitude.value = user?.latitude;
    homeLongitude.value = user?.longitude;
    firstName.value = firstNameOf(user?.fullName ?? '');
    neighborhood.assignAll(_homeService.neighborhood);
    plan.value = PrayerListService.buildPlan(
      _homeService.neighborhood,
      user?.dailyPrayerTarget ?? 5,
    );
  }

  /// "Good morning" / "Good afternoon" / "Good evening" for [now].
  static String greeting(DateTime now) {
    final hour = now.hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  /// The first word of a full name ("Maria Lopez" → "Maria").
  static String firstNameOf(String fullName) {
    final parts = fullName.trim().split(RegExp(r'\s+'));
    return parts.isEmpty ? '' : parts.first;
  }

  Future<void> reload() => _homeService.refreshNeighborhood();

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
    super.onClose();
  }
}
