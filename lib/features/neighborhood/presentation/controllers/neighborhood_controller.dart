import 'package:get/get.dart';
import 'package:gps_cielo/core/models/household_model.dart';
import 'package:gps_cielo/core/services/household_store.dart';
import 'package:gps_cielo/features/auth/presentation/controllers/auth_controller.dart';
import 'package:gps_cielo/features/neighborhood/domain/services/neighborhood_service.dart';
import 'package:gps_cielo/shared/widgets/map/household_osm_map.dart';

enum NeighborhoodViewMode { map, list }

/// Neighborhood tab (Figma "My Neighborhood"): the nearest N homes on a map
/// or in a list, around the saved primary location only. There is no search
/// for other places: the location is chosen once at signup (blueprint §2.1).
class NeighborhoodController extends GetxController {
  final NeighborhoodService _service;
  final AuthController? _auth;

  NeighborhoodController(this._service, {AuthController? auth}) : _auth = auth;

  final viewMode = NeighborhoodViewMode.map.obs;

  /// The nearest N homes around the center: pins and rows.
  final households = <HouseholdModel>[].obs;

  /// No household data exists around the current center (cells).
  final areaUnavailable = false.obs;

  /// Where the homes came from (Melissa-first), or null.
  final areaSourceNote = RxnString();
  final isLoading = false.obs;

  /// The center's label: the saved home address.
  final centerLabel = ''.obs;
  final centerLatitude = RxnDouble();
  final centerLongitude = RxnDouble();

  /// Zooms the map from the +/- buttons.
  final mapHandle = HouseholdMapHandle();

  final List<Worker> _workers = [];

  int get prayedCount => households.where((h) => h.isPrayed).length;
  int get toPrayCount => households.length - prayedCount;

  /// The saved home.
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

  @override
  void onClose() {
    for (final worker in _workers) {
      worker.dispose();
    }
    super.onClose();
  }
}
