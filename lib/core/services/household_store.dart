import 'dart:async';
import 'dart:math' as math;

import 'package:get/get.dart';
import 'package:gps_cielo/core/data/geo_search.dart';
import 'package:gps_cielo/core/data/household_repository.dart';
import 'package:gps_cielo/core/models/household_model.dart';
import 'package:gps_cielo/core/models/user_model.dart';
import 'package:gps_cielo/core/services/location_service.dart';
import 'package:gps_cielo/core/utils/firebase_error_mapper.dart';
import 'package:gps_cielo/core/utils/follow_up_date.dart';
import 'package:gps_cielo/core/utils/search_range.dart';
import 'package:gps_cielo/core/utils/show_snackbar.dart';
import 'package:gps_cielo/features/notifications/data/models/notification_model.dart';
import 'package:gps_cielo/features/notifications/data/repositories/notification_repository.dart';
import 'package:gps_cielo/routes/app_routes.dart';

/// The point nearby households are searched around.
class SearchCenter {
  final double latitude;
  final double longitude;
  final String label;

  /// True for a one-off search location; false for the saved home address.
  final bool isTemporary;

  const SearchCenter({
    required this.latitude,
    required this.longitude,
    required this.label,
    required this.isTemporary,
  });
}

/// App-wide, reactive source of the signed-in user's households.
///
/// Three lists are derived from the same data, so a status change made on
/// any screen shows up on every other screen at once:
///  * [households] — what Home and Neighborhood show: the households within
///    the Settings range around the current center (home or a searched
///    place), limited to the Home count.
///  * [homeHouseholds] — "my neighborhood": the Settings number of
///    households within the Settings range around the **saved home**. The
///    Prayer List works from this list, so searching elsewhere or filtering
///    Home never changes today's prayers.
///  * [trackedHouseholds] — households with activity whose status is known
///    on this device (on screen, loaded by Follow-up, or changed this
///    session). Follow-up uses it to keep its pages current.
///
/// Nothing here grows with the size of the data:
///  * households are read with a progressive nearest-first [GeoSearch] —
///    only as far out as the screens need (Home/Prayer List: the nearest
///    [SearchRange.maxHomes]; Neighborhood: more as the user scrolls);
///  * statuses are read for exactly the households loaded, plus a live
///    listener limited to changes made since sign-in;
///  * totals (prayed, visited, …) are server-side `count()` aggregates.
///
/// Status changes are applied locally first, then written to Firestore.
class HouseholdStore extends GetxService {
  final HouseholdRepository _repository;
  final NotificationRepository _notificationRepository;

  HouseholdStore(this._repository, this._notificationRepository);

  static const int _milestoneEvery = 10;

  /// Households around the current center, nearest first (Home count).
  final households = <HouseholdModel>[].obs;

  /// Households within the range around the current center, nearest first,
  /// as far as read so far. [loadMoreArea] reads further; [areaComplete]
  /// says the whole range is in.
  final areaHouseholds = <HouseholdModel>[].obs;

  /// True once every household within the range has been read.
  final areaComplete = false.obs;

  /// True while [loadMoreArea] reads further out.
  final isLoadingArea = false.obs;

  /// Households [loadMoreArea] was last asked for around this center.
  int _areaTarget = 0;

  /// The user's own neighborhood around the saved home (Settings count).
  final homeHouseholds = <HouseholdModel>[].obs;

  /// Every household with a status, most recently updated first.
  final trackedHouseholds = <HouseholdModel>[].obs;

  final isLoading = false.obs;

  /// Lifetime totals: distinct households ever prayed for / visited.
  final prayedCount = 0.obs;
  final visitedCount = 0.obs;

  /// Server-side totals of the user's statuses (`all`, `isPrayed`,
  /// `isVisited`, `isInvited`, `hasFollowUp`), kept current locally.
  final statusCounts = <String, int>{}.obs;

  /// Where households are currently searched around (null without location).
  final center = Rxn<SearchCenter>();

  /// How many households are shown (nearest first): the Home filter when
  /// set, otherwise the default from Settings (`users/{uid}.radiusHomes`).
  final activeRadius = 0.obs;

  /// The default number of households from Settings.
  final defaultHomes = 0.obs;

  /// True while a Home filter overrides the default number.
  final isRadiusFiltered = false.obs;

  /// The search range from Settings (`users/{uid}.searchRadiusKm`), in
  /// meters. Households are searched within it; the Home filter never
  /// changes it.
  final rangeMeters = RxnDouble();

  /// Households confirmed within the range so far (all of them once
  /// [areaComplete]).
  final foundInRange = 0.obs;

  /// Start of the current prayer cycle (`users/{uid}.prayerCycleStartedAt`).
  final cycleStartedAt = Rxn<DateTime>();

  /// Statuses known on this device, by household id.
  final Map<String, Map<String, dynamic>> _statuses = {};

  /// Household ids whose status was already read (or found missing).
  final Set<String> _statusFetched = {};
  List<HouseholdSnapshot> _docs = const [];
  StreamSubscription<Map<String, Map<String, dynamic>>>? _statusSubscription;

  /// The search on screen and the one around the saved home (the same
  /// object while the view is home).
  GeoSearch? _viewSearch;
  GeoSearch? _homeSearch;

  String? _uid;

  /// The saved home location from the profile.
  String _savedAddress = '';
  double? _savedLatitude;
  double? _savedLongitude;

  /// Default number of households, from Settings.
  int _savedRadius = 0;

  /// Search range in km, from Settings.
  double _rangeKm = 0;

  /// A Home-screen count filter. Never written to the profile.
  int? _radiusFilter;

  int get _radiusHomes => _radiusFilter ?? _savedRadius;

  /// A one-off search location. Never written to the profile.
  ResolvedLocation? _temporaryLocation;

  /// What the current household list was loaded for.
  double? _latitude;
  double? _longitude;
  double _loadedRangeKm = 0;

  /// Households around the saved home, and what they were loaded for.
  List<HouseholdSnapshot> _homeDocs = const [];
  Set<String> _homeIds = const {};
  ({double latitude, double longitude, double rangeKm})? _homeKey;

  /// The "outside your neighborhood" note was shown this session.
  bool _toldOutsideNeighborhood = false;

  /// Incremented per load so a slow, outdated query cannot overwrite a newer one.
  int _loadGeneration = 0;
  int _homeGeneration = 0;

  bool get isTemporarySearch => _temporaryLocation != null;

  /// The signed-in user's id, or null when signed out.
  String? get uid => _uid;

  /// Start of the current prayer cycle, for building models from raw status.
  DateTime? get cycleStart => cycleStartedAt.value;

  /// Points the store at [user], reloading when the account, search center or
  /// range changed. A temporary search location survives profile updates.
  Future<void> bindUser(UserModel user) async {
    final userChanged = user.id != _uid;
    if (userChanged) {
      clear();
      _uid = user.id;
      // Only changes from now on (e.g. from another device); statuses of
      // households on screen are read with them.
      _statusSubscription = _repository
          .watchStatusChanges(
            user.id,
            since: DateTime.now().subtract(const Duration(minutes: 1)),
          )
          .listen(_onStatusChanges, onError: (Object _) {});
      unawaited(refreshCounts());
    }

    _savedAddress = user.address;
    _savedLatitude = user.latitude;
    _savedLongitude = user.longitude;
    // A new default count from Settings replaces any Home filter.
    final countChanged = !userChanged && user.radiusHomes != _savedRadius;
    if (countChanged) _radiusFilter = null;
    _savedRadius = user.radiusHomes;
    _rangeKm = user.searchRadiusKm;
    rangeMeters.value = _rangeKm * 1000;
    final cycleChanged = cycleStartedAt.value != user.prayerCycleStartedAt;
    cycleStartedAt.value = user.prayerCycleStartedAt;
    _publishRadius();
    if (countChanged || cycleChanged) _rebuild();
    await _applyCenter(force: userChanged);
  }

  /// Searches around [location] without changing the saved home address.
  Future<void> searchAround(ResolvedLocation location) async {
    if (_uid == null) return;
    _temporaryLocation = location;
    await _applyCenter();
  }

  /// Shows the [homes] nearest households found within the range. The range
  /// stays as set in Settings and up to [SearchRange.maxHomes] are already
  /// loaded, so nothing is re-queried. Pass null (or the default) to go back
  /// to the default number.
  Future<void> filterRadius(int? homes) async {
    if (_uid == null) return;
    final filter = homes == null || homes <= 0 || homes == _savedRadius
        ? null
        : math.min(homes, SearchRange.maxHomes);
    if (filter == _radiusFilter) return;
    _radiusFilter = filter;
    _publishRadius();
    _rebuild();
  }

  void _publishRadius() {
    activeRadius.value = _radiusHomes;
    defaultHomes.value = _savedRadius;
    isRadiusFiltered.value = _radiusFilter != null;
  }

  /// Forgets a temporary search location without reloading; the next
  /// [bindUser] then searches around the saved home address.
  void discardTemporarySearch() => _temporaryLocation = null;

  /// Returns to searching around the saved home address.
  Future<void> useSavedLocation() async {
    if (_temporaryLocation == null) return;
    _temporaryLocation = null;
    await _applyCenter();
  }

  Future<void> _applyCenter({bool force = false}) async {
    final temporary = _temporaryLocation;
    final latitude = temporary?.latitude ?? _savedLatitude;
    final longitude = temporary?.longitude ?? _savedLongitude;

    center.value = latitude == null || longitude == null
        ? null
        : SearchCenter(
            latitude: latitude,
            longitude: longitude,
            label: temporary != null
                ? (temporary.hasAddress
                      ? temporary.address
                      : temporary.coordinatesLabel)
                : _savedAddress,
            isTemporary: temporary != null,
          );

    final changed =
        latitude != _latitude ||
        longitude != _longitude ||
        _rangeKm != _loadedRangeKm;
    if (force || changed) {
      _latitude = latitude;
      _longitude = longitude;
      _loadedRangeKm = _rangeKm;
      await refreshHouseholds();
    }
    // While searching elsewhere, keep "my neighborhood" current separately.
    await _refreshHomeIfNeeded();
  }

  /// Reloads the households around the saved home (pull to refresh on the
  /// Prayer List), whatever Home is currently showing.
  Future<void> refreshHome() async {
    if (_viewIsHome) return refreshHouseholds();
    _homeKey = null;
    await _refreshHomeIfNeeded();
  }

  ({double latitude, double longitude, double rangeKm})? get _currentHomeKey {
    final latitude = _savedLatitude;
    final longitude = _savedLongitude;
    if (latitude == null || longitude == null) return null;
    return (latitude: latitude, longitude: longitude, rangeKm: _rangeKm);
  }

  bool get _viewIsHome =>
      _temporaryLocation == null &&
      _latitude == _savedLatitude &&
      _longitude == _savedLongitude &&
      _loadedRangeKm == _rangeKm;

  Future<void> _refreshHomeIfNeeded() async {
    final key = _currentHomeKey;
    if (_uid == null || key == _homeKey) return;
    if (key == null) {
      _homeKey = null;
      _homeDocs = const [];
      _rebuild();
      return;
    }
    if (_viewIsHome && _viewSearch != null) {
      // The area on screen is the home area (e.g. a searched place was just
      // saved as home): reuse it instead of querying again.
      _homeGeneration++;
      _setHome(_viewSearch!, key);
      _rebuild();
      return;
    }

    final generation = ++_homeGeneration;
    try {
      final search = _repository.geoSearch(
        latitude: key.latitude,
        longitude: key.longitude,
        radiusKm: key.rangeKm,
      );
      await search.ensure(SearchRange.maxHomes);
      if (generation != _homeGeneration) return;
      _setHome(search, key);
      await _loadStatusesFor(_homeDocs.map((d) => d.id));
      if (generation != _homeGeneration) return;
      _rebuild();
    } catch (_) {
      // The Prayer List keeps its previous neighborhood; Home shows errors.
    }
  }

  void _setHome(
    GeoSearch search,
    ({double latitude, double longitude, double rangeKm})? key,
  ) {
    _homeSearch = search;
    _homeDocs = [for (final hit in search.confirmed) hit.doc];
    _homeIds = {for (final d in _homeDocs) d.id};
    _homeKey = key;
  }

  void clear() {
    _loadGeneration++;
    _homeGeneration++;
    isLoading.value = false;
    _statusSubscription?.cancel();
    _statusSubscription = null;
    _uid = null;
    _savedAddress = '';
    _savedLatitude = null;
    _savedLongitude = null;
    _savedRadius = 0;
    _rangeKm = 0;
    _radiusFilter = null;
    _toldOutsideNeighborhood = false;
    activeRadius.value = 0;
    defaultHomes.value = 0;
    isRadiusFiltered.value = false;
    foundInRange.value = 0;
    _temporaryLocation = null;
    _latitude = null;
    _longitude = null;
    _loadedRangeKm = 0;
    _homeDocs = const [];
    _homeIds = const {};
    _homeKey = null;
    _viewSearch = null;
    _homeSearch = null;
    areaComplete.value = false;
    isLoadingArea.value = false;
    center.value = null;
    rangeMeters.value = null;
    cycleStartedAt.value = null;
    _statuses.clear();
    _statusFetched.clear();
    statusCounts.clear();
    _docs = const [];
    households.clear();
    areaHouseholds.clear();
    homeHouseholds.clear();
    trackedHouseholds.clear();
    prayedCount.value = 0;
    visitedCount.value = 0;
  }

  Future<void> refreshHouseholds() async {
    final latitude = _latitude;
    final longitude = _longitude;
    if (_uid == null || latitude == null || longitude == null) {
      _docs = const [];
      _rebuild();
      return;
    }

    final generation = ++_loadGeneration;
    _areaTarget = 0;
    isLoadingArea.value = false;
    isLoading.value = true;
    try {
      final search = _repository.geoSearch(
        latitude: latitude,
        longitude: longitude,
        radiusKm: _loadedRangeKm,
      );
      // Enough for the largest Home count; Neighborhood reads more on scroll.
      await search.ensure(SearchRange.maxHomes);
      if (generation != _loadGeneration) return;
      _viewSearch = search;
      _publishArea(search);
      if (_viewIsHome) {
        _setHome(search, _currentHomeKey);
        _homeGeneration++;
      }
      await _loadStatusesFor(_docs.map((d) => d.id));
      if (generation != _loadGeneration) return;
      _rebuild();
    } catch (error) {
      if (generation != _loadGeneration) return;
      SnackbarService.showError(
        'Could not load households',
        FirebaseErrorMapper.message(error),
      );
    } finally {
      if (generation == _loadGeneration) isLoading.value = false;
    }
  }

  void _publishArea(GeoSearch search) {
    _docs = [for (final hit in search.confirmed) hit.doc];
    areaComplete.value = search.isComplete;
  }

  /// Reads further out until at least [count] households around the current
  /// center are known (Neighborhood paging). A request made while a read is
  /// running raises its target instead of starting another; reads for an
  /// area no longer on screen are dropped.
  Future<void> loadMoreArea(int count) async {
    if (count > _areaTarget) _areaTarget = count;
    final search = _viewSearch;
    if (search == null || search.isComplete || isLoadingArea.value) return;
    if (search.confirmed.length >= _areaTarget) return;
    final generation = _loadGeneration;
    isLoadingArea.value = true;
    try {
      while (!search.isComplete && search.confirmed.length < _areaTarget) {
        await search.ensure(_areaTarget);
        if (generation != _loadGeneration || search != _viewSearch) return;
        _publishArea(search);
        await _loadStatusesFor(_docs.map((d) => d.id));
        if (generation != _loadGeneration) return;
        _rebuild();
      }
    } catch (error) {
      if (generation == _loadGeneration) {
        SnackbarService.showError(
          'Could not load more households',
          FirebaseErrorMapper.message(error),
        );
      }
    } finally {
      isLoadingArea.value = false;
    }
  }

  /// Whether [id] is within the Settings range of the saved home ("my
  /// neighborhood"): true or false when known, null when the home search
  /// has not read far enough to tell.
  bool? isNearHome(String id) {
    if (_homeIds.contains(id)) return true;
    final search = _homeSearch;
    if (search == null) return null;
    final meters = search.distanceOf(id);
    if (meters != null) return meters <= search.maxMeters;
    return search.isComplete ? false : null;
  }

  /// The status of [id] if known on this device (null: unknown, not
  /// necessarily missing).
  Map<String, dynamic>? statusOf(String id) => _statuses[id];

  /// Whether this device knows the status of [id] (read, or none exists).
  bool knowsStatusOf(String id) =>
      _statuses.containsKey(id) || _statusFetched.contains(id);

  /// Adds statuses read elsewhere (e.g. a Follow-up page) without another
  /// read. Changes made on this device win.
  void rememberStatuses(Map<String, Map<String, dynamic>> statuses) {
    var changed = false;
    statuses.forEach((id, status) {
      _statusFetched.add(id);
      if (!_statuses.containsKey(id)) {
        _statuses[id] = status;
        changed = true;
      }
    });
    if (changed) _rebuild();
  }

  /// Reads statuses of households not read yet, 30 per query.
  Future<void> _loadStatusesFor(Iterable<String> ids) async {
    final uid = _uid;
    if (uid == null) return;
    final missing = ids.where((id) => !knowsStatusOf(id)).toList();
    if (missing.isEmpty) return;
    try {
      final found = await _repository.fetchStatuses(uid, missing);
      if (uid != _uid) return;
      _statusFetched.addAll(missing);
      found.forEach((id, status) => _statuses.putIfAbsent(id, () => status));
    } catch (_) {
      // Shown without status; read again next time they are loaded.
    }
  }

  /// Re-reads the server-side totals.
  Future<void> refreshCounts() async {
    final uid = _uid;
    if (uid == null) return;
    try {
      final counts = await _repository.countStatuses(uid);
      if (uid != _uid) return;
      statusCounts.assignAll(counts);
      _publishCounts();
    } catch (_) {
      // Keep the last known totals.
    }
  }

  void _publishCounts() {
    prayedCount.value = statusCounts['isPrayed'] ?? 0;
    visitedCount.value = statusCounts['isVisited'] ?? 0;
  }

  /// Adjusts the totals for a local change from [before] to [after].
  void _countChange(Map<String, dynamic>? before, Map<String, dynamic>? after) {
    if (statusCounts.isEmpty && _uid == null) return;
    final next = Map<String, int>.of(statusCounts);
    int flag(Map<String, dynamic>? s, String f) => s?[f] == true ? 1 : 0;
    if ((before == null) != (after == null)) {
      next['all'] = (next['all'] ?? 0) + (after == null ? -1 : 1);
    }
    for (final f in const [
      'isPrayed',
      'isVisited',
      'isInvited',
      'hasFollowUp',
    ]) {
      final d = flag(after, f) - flag(before, f);
      if (d != 0) next[f] = ((next[f] ?? 0) + d).clamp(0, 1 << 31);
    }
    statusCounts.assignAll(next);
    _publishCounts();
  }

  /// Finds a household in any of the lists.
  HouseholdModel? findById(String id) {
    return households.firstWhereOrNull((h) => h.id == id) ??
        areaHouseholds.firstWhereOrNull((h) => h.id == id) ??
        homeHouseholds.firstWhereOrNull((h) => h.id == id) ??
        trackedHouseholds.firstWhereOrNull((h) => h.id == id);
  }

  /// Marks [id] prayed for (in the current cycle), or undoes it.
  Future<void> togglePray(String id) async {
    final current = findById(id);
    if (current == null) return;
    await saveHousehold(current.copyWith(isPrayed: !current.isPrayed));
  }

  Future<void> toggleVisited(String id) async {
    final current = findById(id);
    if (current == null) return;
    await saveHousehold(current.copyWith(isVisited: !current.isVisited));
  }

  Future<void> toggleFollowUp(String id) async {
    final current = findById(id);
    if (current == null) return;
    await saveHousehold(
      current.copyWith(
        hasFollowUp: !current.hasFollowUp,
        followUpDate: current.followUpDate ?? defaultFollowUpDate(),
      ),
    );
  }

  /// Persists the status fields of [updated] for the signed-in user.
  Future<void> saveHousehold(HouseholdModel updated) async {
    final uid = _uid;
    if (uid == null) return;

    final current = findById(updated.id);
    if (current != null && current.hasSameStatusAs(updated)) return;

    final previous = _statuses[updated.id];
    final wasPrayedInCycle =
        current?.isPrayed ??
        HouseholdModel.prayedInCycle(previous, cycleStartedAt.value);
    final becamePrayed = updated.isPrayed && !wasPrayedInCycle;
    final firstPrayer = becamePrayed && previous?['isPrayed'] != true;
    final becameFollowUp =
        updated.hasFollowUp && !(current?.hasFollowUp ?? false);

    // A prayer outside "my neighborhood" (a searched place, or beyond the
    // Settings count) is saved but is not part of the prayer round. Say so
    // once per session, so the Prayer List never seems to lose it.
    if (becamePrayed &&
        !_toldOutsideNeighborhood &&
        homeHouseholds.isNotEmpty &&
        !homeHouseholds.any((h) => h.id == updated.id)) {
      _toldOutsideNeighborhood = true;
      SnackbarService.showInfo(
        'Prayer saved',
        'This home is outside your neighborhood, so it is not on your '
            'Prayer List and does not count toward today\'s goal.',
      );
    }

    // Optimistic update of every list; the snapshot listener confirms it.
    final next = <String, dynamic>{
      ...?previous,
      ...updated.toStatusFirestore(),
    };
    if (becamePrayed) {
      next['prayedAt'] = DateTime.now();
    } else if (!updated.isPrayed) {
      next.remove('prayedAt');
    }
    next['updatedAt'] = DateTime.now();
    _statuses[updated.id] = next;
    _countChange(previous, next);
    _rebuild();

    try {
      final write = _repository.saveStatus(
        uid: uid,
        household: updated,
        wasPrayed: wasPrayedInCycle,
      );
      // A notification failing (even synchronously) must never undo a
      // prayer that is already being written.
      try {
        if (firstPrayer) _notifyMilestoneIfReached(prayedCount.value);
        if (becameFollowUp) _notifyFollowUpScheduled(updated);
      } catch (_) {}
      await write;
    } catch (error) {
      _countChange(next, previous);
      if (previous == null) {
        _statuses.remove(updated.id);
      } else {
        _statuses[updated.id] = previous;
      }
      _rebuild();
      SnackbarService.showError(
        'Could not save',
        FirebaseErrorMapper.message(error),
      );
    }
  }

  /// Changes since sign-in (this device's writes echo back too).
  void _onStatusChanges(Map<String, Map<String, dynamic>> changes) {
    if (changes.isEmpty) return;
    var remote = false;
    changes.forEach((id, status) {
      final known = _statuses[id];
      // Our own write echoing back carries the same flags.
      if (known == null || !_sameFlags(known, status)) remote = true;
      _statuses[id] = status;
      _statusFetched.add(id);
    });
    _rebuild();
    if (remote) unawaited(refreshCounts());
  }

  static bool _sameFlags(Map<String, dynamic> a, Map<String, dynamic> b) {
    for (final f in const [
      'isPrayed',
      'isVisited',
      'isInvited',
      'hasFollowUp',
    ]) {
      if ((a[f] == true) != (b[f] == true)) return false;
    }
    return a['notes'] == b['notes'] && a['followUpDate'] == b['followUpDate'];
  }

  List<HouseholdModel> _fromDocs(List<HouseholdSnapshot> docs) {
    final cycleStart = cycleStartedAt.value;
    return [
      for (var i = 0; i < docs.length; i++)
        HouseholdModel.fromFirestore(
          doc: docs[i],
          status: _statuses[docs[i].id],
          number: i + 1,
          cycleStart: cycleStart,
        ),
    ];
  }

  void _rebuild() {
    final area = _fromDocs(_docs);
    foundInRange.value = area.length;
    // Nearest first, so the count keeps the closest homes.
    households.assignAll(area.take(_radiusHomes));
    areaHouseholds.assignAll(area);

    final home = _fromDocs(_homeDocs);
    homeHouseholds.assignAll(home.take(_savedRadius));

    // Tracked: prefer the full household (with location) when it is loaded.
    final loaded = {
      for (final h in [...area, ...home]) h.id: h,
    };
    final cycleStart = cycleStartedAt.value;
    final tracked = <HouseholdModel>[];
    for (final entry in _statuses.entries) {
      final model =
          loaded[entry.key] ??
          HouseholdModel.fromStatus(
            id: entry.key,
            status: entry.value,
            number: 0,
            cycleStart: cycleStart,
          );
      if (model.hasActivity) tracked.add(model);
    }
    tracked.sort((a, b) {
      final at = a.updatedAt, bt = b.updatedAt;
      if (at == null || bt == null) return at == null ? 1 : -1;
      return bt.compareTo(at);
    });
    trackedHouseholds.assignAll([
      for (var i = 0; i < tracked.length; i++)
        tracked[i].copyWith(number: i + 1),
    ]);
  }

  void _notifyMilestoneIfReached(int newCount) {
    if (newCount <= 0 || newCount % _milestoneEvery != 0) return;
    _notificationRepository
        .addNotification(
          title: 'Milestone Reached! 🎉',
          message:
              'Praise God! You have prayed for $newCount households. Keep pressing forward!',
          type: NotificationType.milestone,
          actionRoute: AppRoutes.prayerList,
        )
        .catchError((_) {});
  }

  void _notifyFollowUpScheduled(HouseholdModel household) {
    _notificationRepository
        .addNotification(
          title: 'Follow-up Scheduled',
          message:
              'Follow-up with ${household.residentName} (${household.address}) on ${household.followUpDate ?? defaultFollowUpDate()}.',
          type: NotificationType.followUpDue,
          actionRoute: AppRoutes.followUp,
        )
        .catchError((_) {});
  }

  @override
  void onClose() {
    _statusSubscription?.cancel();
    super.onClose();
  }
}
