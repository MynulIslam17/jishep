import 'package:get/get.dart';
import 'package:gps_cielo/core/models/household_model.dart';
import 'package:gps_cielo/core/services/household_store.dart';
import 'package:gps_cielo/core/utils/search_range.dart';
import 'package:gps_cielo/features/neighborhood/domain/services/neighborhood_service.dart';
import 'package:gps_cielo/shared/widgets/map/household_osm_map.dart';

enum NeighborhoodViewMode { map, list }

class NeighborhoodController extends GetxController {
  final NeighborhoodService _service;

  NeighborhoodController(this._service);

  final viewMode = NeighborhoodViewMode.map.obs;

  /// The nearest households (Home count), pinned on the map.
  final households = <HouseholdModel>[].obs;

  /// Households within the range read so far, nearest first.
  final areaHouseholds = <HouseholdModel>[].obs;

  /// True once every household within the range has been read (until then
  /// counts show as "N+").
  final areaComplete = false.obs;

  /// True while households further out are being read.
  final isLoadingMore = false.obs;

  /// The list shows [pageSize] more households each time the user scrolls
  /// to the end; households further out are read from Firestore only as the
  /// list reaches them (one page ahead).
  static const int pageSize = 10;
  final visibleCount = pageSize.obs;

  /// False: the list shows the neighborhood (the same homes as Home, the
  /// map and the Prayer List). True: it pages through everything in range.
  final showAllInRange = false.obs;

  /// True when Home shows a searched place rather than the saved home.
  final isTemporary = false.obs;

  List<HouseholdModel> get pagedHouseholds => showAllInRange.value
      ? areaHouseholds.take(visibleCount.value).toList()
      : households.toList();

  bool get hasMore =>
      showAllInRange.value &&
      (visibleCount.value < areaHouseholds.length || !areaComplete.value);

  /// More households are in range than in the neighborhood.
  bool get hasMoreInRange =>
      areaHouseholds.length > households.length || !areaComplete.value;

  /// Pages through every household in range, starting after the
  /// neighborhood (or back to only the neighborhood).
  void setShowAllInRange(bool value) {
    if (showAllInRange.value == value) return;
    showAllInRange.value = value;
    _pageWaiting = false;
    visibleCount.value = value
        ? ((households.length ~/ pageSize) + 1) * pageSize
        : pageSize;
    if (value) _prefetch();
  }

  /// Shows the next page. Returns false when everything is shown.
  bool loadMore() {
    if (!hasMore) return false;
    // Wait for the read when the next page is not in yet.
    if (visibleCount.value >= areaHouseholds.length) {
      _pageWaiting = true;
      _prefetch();
      return false;
    }
    visibleCount.value += pageSize;
    _prefetch();
    return true;
  }

  /// A page was asked for before it was read; shown once it arrives.
  bool _pageWaiting = false;

  void _onArea(List<HouseholdModel> area) {
    areaHouseholds.assignAll(area);
    if (_pageWaiting && area.length > visibleCount.value) {
      _pageWaiting = false;
      visibleCount.value += pageSize;
      _prefetch();
    } else if (area.isNotEmpty &&
        areaComplete.value &&
        area.length <= visibleCount.value) {
      // The range held nothing more. (assignAll first reports an empty
      // list, then the new one: only the real list may end the wait.)
      _pageWaiting = false;
    }
  }

  void _resetPaging() {
    _pageWaiting = false;
    visibleCount.value = pageSize;
    showAllInRange.value = false;
  }

  /// Reads two pages past the visible ones, so scrolling rarely waits —
  /// including the last read, which only confirms nothing more is in range.
  void _prefetch() {
    if (areaComplete.value) return;
    final wanted = visibleCount.value + 2 * pageSize;
    if (areaHouseholds.length >= wanted) return;
    _service.loadMoreArea(wanted);
  }

  final selectedHousehold = Rxn<HouseholdModel>();
  final radiusHomes = 10.obs;
  final rangeMeters = RxnDouble();
  final isLoading = false.obs;
  final centerLatitude = RxnDouble();
  final centerLongitude = RxnDouble();

  /// Zooms the neighborhood map from the +/- buttons.
  final mapHandle = HouseholdMapHandle();

  final List<Worker> _workers = [];

  @override
  void onInit() {
    super.onInit();
    households.assignAll(_service.households);
    areaHouseholds.assignAll(_service.areaHouseholds);
    areaComplete.value = _service.areaComplete.value;
    isLoadingMore.value = _service.isLoadingArea.value;
    rangeMeters.value = _service.rangeMeters.value;
    isLoading.value = _service.isLoading.value;
    _applyRadius(_service.activeRadius.value);
    _applyCenter(_service.center.value);

    _workers.addAll([
      ever(_service.center, (SearchCenter? c) {
        _applyCenter(c);
        _resetPaging(); // a new area starts at page one
      }),
      ever(_service.rangeMeters, (_) => _resetPaging()),
      ever(_service.areaHouseholds, _onArea),
      ever(_service.areaComplete, (bool c) => areaComplete.value = c),
      ever(_service.isLoadingArea, (bool l) => isLoadingMore.value = l),
      ever(_service.rangeMeters, (double? m) => rangeMeters.value = m),
      ever(_service.households, households.assignAll),
      ever(_service.isLoading, (bool loading) => isLoading.value = loading),
      ever(_service.activeRadius, _applyRadius),
    ]);
  }

  /// Same range as Home (the Home filter, or the default from Settings).
  void _applyRadius(int homes) {
    if (homes > 0) radiusHomes.value = homes;
  }

  /// The map follows the active search center (home or a searched place).
  void _applyCenter(SearchCenter? center) {
    centerLatitude.value = center?.latitude;
    centerLongitude.value = center?.longitude;
    isTemporary.value = center?.isTemporary ?? false;
  }

  /// "Nearest 10 homes · within 1.2 km".
  String get rangeLabel {
    final meters = rangeMeters.value;
    return SearchRange.label(
      shown: households.length,
      requested: radiusHomes.value,
      rangeKm: meters == null || isLoading.value ? null : meters / 1000,
    );
  }

  Future<void> loadHouseholds() => _service.refreshHouseholds();

  void switchViewMode(NeighborhoodViewMode mode) {
    viewMode.value = mode;
  }

  void selectHousehold(HouseholdModel household) {
    selectedHousehold.value = household;
  }

  Future<void> zoomIn() => mapHandle.zoomIn();

  Future<void> zoomOut() => mapHandle.zoomOut();

  Future<void> togglePray(HouseholdModel household) {
    return _service.togglePray(household.id);
  }

  Future<void> toggleVisit(HouseholdModel household) {
    return _service.toggleVisit(household.id);
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
