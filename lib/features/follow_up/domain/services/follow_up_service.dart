import 'package:get/get.dart';
import 'package:gps_cielo/core/data/household_repository.dart';
import 'package:gps_cielo/core/models/household_model.dart';
import 'package:gps_cielo/core/services/household_store.dart';

/// One page of Follow-up households from Firestore.
class FollowUpPage {
  const FollowUpPage({
    required this.households,
    required this.hasMore,
    this.cursor,
  });

  final List<HouseholdModel> households;
  final bool hasMore;
  final HouseholdSnapshot? cursor;
}

class FollowUpService {
  final HouseholdStore _store;
  final HouseholdRepository _repository;

  FollowUpService(this._store, this._repository);

  /// Statuses known on this device (loaded pages, nearby households and
  /// changes made since sign-in), used to keep loaded items current and to
  /// show households changed after the list was loaded.
  RxList<HouseholdModel> get households => _store.trackedHouseholds;

  RxBool get isLoading => _store.isLoading;

  /// Server-side totals per status flag (`all`, `isPrayed`, …); empty until
  /// read.
  RxMap<String, int> get statusCounts => _store.statusCounts;

  /// Whether the latest status of [id] is known on this device.
  bool knowsStatusOf(String id) => _store.knowsStatusOf(id);

  /// False for households known to be away from the saved home's area; null
  /// when that is not known yet.
  bool? isNearHome(String id) => _store.isNearHome(id);

  /// Loads the next [pageSize] households from Firestore, most recently
  /// updated first. [onlyWhere] filters on a status flag (e.g. `isPrayed`).
  Future<FollowUpPage> fetchPage({
    String? onlyWhere,
    HouseholdSnapshot? startAfter,
    int pageSize = 20,
  }) async {
    final uid = _store.uid;
    if (uid == null) {
      return const FollowUpPage(households: [], hasMore: false);
    }
    final page = await _repository.fetchStatusPage(
      uid: uid,
      onlyWhere: onlyWhere,
      limit: pageSize,
      startAfter: startAfter,
    );
    // Share what was read, so the list stays current without another read.
    _store.rememberStatuses({
      for (final doc in page.docs) doc.id: doc.data() ?? const {},
    });
    return FollowUpPage(
      households: [
        for (final doc in page.docs)
          HouseholdModel.fromStatus(
            id: doc.id,
            status: doc.data() ?? const {},
            number: 0,
            cycleStart: _store.cycleStart,
          ),
      ],
      hasMore: page.hasMore,
      cursor: page.cursor,
    );
  }

  Future<void> refreshHouseholds() => _store.refreshHome();

  Future<void> updateHousehold(HouseholdModel household) {
    return _store.saveHousehold(household);
  }
}
