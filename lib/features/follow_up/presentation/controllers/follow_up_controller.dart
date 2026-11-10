import 'package:get/get.dart';
import 'package:gps_cielo/core/data/household_repository.dart';
import 'package:gps_cielo/core/models/household_model.dart';
import 'package:gps_cielo/core/utils/firebase_error_mapper.dart';
import 'package:gps_cielo/features/follow_up/domain/services/follow_up_service.dart';

enum FollowUpTab {
  all('All', null),
  prayed('Prayed', 'isPrayed'),
  invited('Invited', 'isInvited'),
  visited('Visited', 'isVisited'),
  followUp('Follow Up', 'hasFollowUp');

  final String label;

  /// The Firestore status flag this tab filters on (null: everything).
  final String? field;
  const FollowUpTab(this.label, this.field);

  bool matches(HouseholdModel h) => switch (this) {
    FollowUpTab.all => true,
    // Prayed in any cycle: Follow-up is the full history.
    FollowUpTab.prayed => h.isPrayed || h.prayedAt != null,
    FollowUpTab.invited => h.isInvited,
    FollowUpTab.visited => h.isVisited,
    FollowUpTab.followUp => h.hasFollowUp,
  };
}

/// Follow-up list, loaded from Firestore a page at a time (newest first).
///
/// Loaded items are kept current from the live statuses, and households
/// changed after loading appear at the top without a reload.
class FollowUpController extends GetxController {
  final FollowUpService _service;

  FollowUpController(this._service);

  static const int pageSize = 20;

  /// Live statuses of every tracked household.
  final allHouseholds = <HouseholdModel>[].obs;
  final selectedTab = FollowUpTab.all.obs;
  final searchQuery = ''.obs;

  /// The households loaded from Firestore for the selected tab, in order.
  final _loaded = <HouseholdModel>[].obs;
  HouseholdSnapshot? _cursor;
  DateTime? _loadedAt;

  final hasMore = false.obs;
  final isLoadingFirst = false.obs;
  final isLoadingMore = false.obs;
  final loadError = RxnString();

  /// Increments per (re)load so a slow page of an old tab is ignored.
  int _generation = 0;

  final List<Worker> _workers = [];

  /// Only households known to be away from home are labeled.
  bool isNearHome(HouseholdModel household) =>
      _service.isNearHome(household.id) != false;

  /// How many households each tab holds (shown on the tabs): the
  /// server-side totals, or what is known locally until they are read.
  int countFor(FollowUpTab tab) {
    final counts = _service.statusCounts;
    final total = counts[tab.field ?? 'all'];
    if (total != null) return total;
    return allHouseholds.where(tab.matches).length;
  }

  /// Loaded households (with their latest status) plus any changed since
  /// loading, newest first, filtered by the search text.
  List<HouseholdModel> get filteredHouseholds {
    final tab = selectedTab.value;
    final live = {for (final h in allHouseholds) h.id: h};
    final seen = <String>{};
    final result = <HouseholdModel>[];

    for (final item in _loaded) {
      // A known status missing from the live list has no activity left
      // (e.g. un-prayed): drop it.
      final current =
          live[item.id] ?? (_service.knowsStatusOf(item.id) ? null : item);
      if (current == null) continue;
      if (seen.add(item.id) && tab.matches(current)) result.add(current);
    }
    // Changed after the list was loaded (e.g. just prayed for elsewhere).
    final since = _loadedAt;
    if (since != null) {
      for (final h in allHouseholds) {
        final at = h.updatedAt;
        if (at != null &&
            at.isAfter(since) &&
            tab.matches(h) &&
            seen.add(h.id)) {
          result.add(h);
        }
      }
    }
    result.sort((a, b) {
      final at = a.updatedAt, bt = b.updatedAt;
      if (at == null || bt == null) return at == null ? 1 : -1;
      return bt.compareTo(at);
    });

    final query = searchQuery.value.trim().toLowerCase();
    final shown = query.isEmpty
        ? result
        : result.where((h) {
            return h.residentName.toLowerCase().contains(query) ||
                h.address.toLowerCase().contains(query) ||
                (h.notes ?? '').toLowerCase().contains(query);
          }).toList();
    return [
      for (var i = 0; i < shown.length; i++) shown[i].copyWith(number: i + 1),
    ];
  }

  @override
  void onInit() {
    super.onInit();
    allHouseholds.assignAll(_service.households);
    _workers.add(ever(_service.households, allHouseholds.assignAll));
    loadFirstPage();
  }

  /// Loads the first page of the selected tab from Firestore.
  Future<void> loadFirstPage() async {
    final generation = ++_generation;
    isLoadingFirst.value = true;
    isLoadingMore.value = false;
    loadError.value = null;
    try {
      final page = await _service.fetchPage(
        onlyWhere: selectedTab.value.field,
        pageSize: pageSize,
      );
      if (generation != _generation) return;
      _loadedAt = DateTime.now();
      _cursor = page.cursor;
      hasMore.value = page.hasMore;
      _loaded.assignAll(page.households);
    } catch (error) {
      if (generation != _generation) return;
      loadError.value = FirebaseErrorMapper.message(error);
    } finally {
      if (generation == _generation) isLoadingFirst.value = false;
    }
  }

  /// Loads the next page, if there is one and none is loading.
  Future<void> loadMore() async {
    if (!hasMore.value || isLoadingMore.value || isLoadingFirst.value) return;
    final generation = _generation;
    isLoadingMore.value = true;
    loadError.value = null;
    try {
      final page = await _service.fetchPage(
        onlyWhere: selectedTab.value.field,
        startAfter: _cursor,
        pageSize: pageSize,
      );
      if (generation != _generation) return;
      _cursor = page.cursor;
      hasMore.value = page.hasMore;
      final known = {for (final h in _loaded) h.id};
      _loaded.addAll(page.households.where((h) => !known.contains(h.id)));
    } catch (error) {
      if (generation != _generation) return;
      loadError.value = FirebaseErrorMapper.message(error);
    } finally {
      if (generation == _generation) isLoadingMore.value = false;
    }
  }

  /// Pull to refresh: reload the first page.
  Future<void> loadFollowUps() => loadFirstPage();

  void selectTab(FollowUpTab tab) {
    if (selectedTab.value == tab) return;
    selectedTab.value = tab;
    _loaded.clear();
    _cursor = null;
    hasMore.value = false;
    loadFirstPage();
  }

  void updateSearch(String query) {
    searchQuery.value = query;
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
