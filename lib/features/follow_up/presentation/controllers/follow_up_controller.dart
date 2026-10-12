import 'package:get/get.dart';
import 'package:gps_cielo/core/models/household_model.dart';
import 'package:gps_cielo/features/follow_up/domain/services/follow_up_service.dart';

enum FollowUpTab {
  prayed('Prayed'),
  invited('Invited'),
  visited('Visited'),
  followUp('Follow Up'),
  all('All');

  final String label;
  const FollowUpTab(this.label);
}

class FollowUpController extends GetxController {
  final FollowUpService _service;

  FollowUpController(this._service);

  final allHouseholds = <HouseholdModel>[].obs;
  final selectedTab = FollowUpTab.all.obs;
  final searchQuery = ''.obs;
  final isLoading = false.obs;

  List<HouseholdModel> get filteredHouseholds {
    final query = searchQuery.value.trim().toLowerCase();

    return allHouseholds.where((h) {
      // 1. Filter by Tab
      final matchesTab = switch (selectedTab.value) {
        FollowUpTab.prayed => h.isPrayed,
        FollowUpTab.invited => h.isInvited,
        FollowUpTab.visited => h.isVisited,
        FollowUpTab.followUp => h.hasFollowUp,
        FollowUpTab.all => true,
      };

      if (!matchesTab) return false;

      // 2. Filter by Search Query
      if (query.isEmpty) return true;

      final nameMatch = h.residentName.toLowerCase().contains(query);
      final addressMatch = h.address.toLowerCase().contains(query);
      final notesMatch = (h.notes ?? '').toLowerCase().contains(query);

      return nameMatch || addressMatch || notesMatch;
    }).toList();
  }

  final List<Worker> _workers = [];

  @override
  void onInit() {
    super.onInit();
    allHouseholds.assignAll(_service.households);
    isLoading.value = _service.isLoading.value;

    _workers.addAll([
      ever(_service.households, allHouseholds.assignAll),
      ever(_service.isLoading, (bool loading) => isLoading.value = loading),
    ]);
  }

  Future<void> loadFollowUps() => _service.refreshHouseholds();

  void selectTab(FollowUpTab tab) {
    selectedTab.value = tab;
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
