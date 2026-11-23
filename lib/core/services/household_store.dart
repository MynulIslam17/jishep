import 'dart:async';
import 'dart:math' as math;

import 'package:get/get.dart';
import 'package:gps_cielo/core/config/feature_flags.dart';
import 'package:gps_cielo/core/constants/firestore_paths.dart';
import 'package:gps_cielo/core/data/area_search.dart';
import 'package:gps_cielo/core/data/geo_record.dart';
import 'package:gps_cielo/core/data/owner_discovery.dart';
import 'package:gps_cielo/core/data/household_repository.dart';
import 'package:gps_cielo/core/models/household_model.dart';
import 'package:gps_cielo/core/models/prayer_round.dart';
import 'package:gps_cielo/core/models/user_model.dart';
import 'package:gps_cielo/core/services/location_service.dart';
import 'package:gps_cielo/core/utils/firebase_error_mapper.dart';
import 'package:gps_cielo/core/utils/follow_up_date.dart';
import 'package:gps_cielo/core/utils/geohash.dart';
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
///  * households are read with a progressive nearest-first [GeoSearch]
///    (or, with `FeatureFlags.useCellHouseholds`, the nearest 50 from the
///    Overture cells around the center: see `CellArea`) —
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

  /// Lifetime prayers over every round (`prayer_log`, one event per home
  /// per round). Never below [prayedCount]: prayers saved before the
  /// history existed have no event but each was at least one prayer.
  final prayersOffered = 0.obs;
  int _prayerEvents = 0;

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

  /// Recorded owner names (Melissa address checks), by household id.
  final Map<String, String> _owners = {};

  /// Second recorded owners, by household id.
  final Map<String, String> _secondOwners = {};

  /// Household ids whose status was already read (or found missing).
  final Set<String> _statusFetched = {};
  List<GeoRecord> _records = const [];

  /// True when no household data exists around the current center (cells
  /// only): screens show "This area isn't available yet".
  final areaUnavailable = false.obs;

  /// Where the area's homes came from, when that matters to the user
  /// (Melissa-first neighborhood): null for the plain Overture list.
  final areaSourceNote = RxnString();

  /// The same, around the saved home (Prayer List).
  final homeUnavailable = false.obs;

  /// Where "my neighborhood" came from, or why it is empty (Melissa-only
  /// mode: "12 homes found so far", "…not available for this area yet").
  final homeSourceNote = RxnString();
  StreamSubscription<Map<String, Map<String, dynamic>>>? _statusSubscription;

  /// The search on screen and the one around the saved home (the same
  /// object while the view is home).
  AreaSearch? _viewSearch;
  AreaSearch? _homeSearch;

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
  List<GeoRecord> _homeRecords = const [];
  Set<String> _homeIds = const {};
  ({double latitude, double longitude, double rangeKm})? _homeKey;

  /// The homes of the current prayer round, fixed when the round is first
  /// shown (`prayer_rounds/{roundId}.members`). Null until known, or when
  /// the round's document cannot be read (then the nearest homes are used,
  /// as before rounds were recorded).
  PrayerRound? _round;

  /// The round [_round] belongs to, and whether its document was read.
  String? _roundId;
  bool _roundKnown = false;

  /// Rounds recorded on this device, by id (a new round's homes are known
  /// before its document is read back).
  final Map<String, PrayerRound> _roundCache = {};

  /// A saved home this far from the round's center is a new neighborhood.
  static const double roundMoveMeters = 100;

  /// The "outside your neighborhood" note was shown this session.
  bool _toldOutsideNeighborhood = false;

  /// Incremented per load so a slow, outdated query cannot overwrite a newer one.
  int _loadGeneration = 0;
  int _homeGeneration = 0;

  bool get isTemporarySearch => _temporaryLocation != null;

  /// The saved home location, or null when none is set.
  ({double latitude, double longitude})? get homePoint {
    final latitude = _savedLatitude;
    final longitude = _savedLongitude;
    if (latitude == null || longitude == null) return null;
    return (latitude: latitude, longitude: longitude);
  }

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
      unawaited(_loadOwnerNames(user.id));
    }

    _savedAddress = user.address;
    _savedLatitude = user.latitude;
    _savedLongitude = user.longitude;
    // A new default count from Settings replaces any Home filter.
    final countChanged = !userChanged && user.radiusHomes != _savedRadius;
    if (countChanged) _radiusFilter = null;
    _savedRadius = user.radiusHomes;
    _rangeKm = user.searchRadiusKm;
    rangeMeters.value = _viewSearch?.extentMeters ?? _rangeKm * 1000;
    final cycleChanged = cycleStartedAt.value != user.prayerCycleStartedAt;
    cycleStartedAt.value = user.prayerCycleStartedAt;
    _publishRadius();
    if (countChanged || cycleChanged) _rebuild();
    unawaited(_loadRound());
    if (countChanged) unawaited(_maybeFixRound());
    await _applyCenter(force: userChanged);
    // The saved home may have moved: a new neighborhood for the round.
    unawaited(_maybeFixRound());
  }

  /// Reads the homes of the current round (once per round).
  Future<void> _loadRound() async {
    final uid = _uid;
    if (uid == null) return;
    final id = FirestorePaths.roundId(cycleStartedAt.value);
    if (id == _roundId) return;
    _roundId = id;
    _round = _roundCache[id];
    _roundKnown = _round != null;
    if (_roundKnown) {
      _rebuild();
      return;
    }
    try {
      final round = await _repository.fetchRound(uid, id);
      if (uid != _uid || id != _roundId) return;
      _roundKnown = true;
      if (round != null) {
        _round = _roundCache[id] = round;
        await _loadStatusesFor(round.ids);
        if (uid != _uid || id != _roundId) return;
        _rebuild();
      }
      await _maybeFixRound();
    } catch (_) {
      // Unreadable (rules without prayer_rounds, offline): the nearest
      // homes are shown as before; nothing is fixed or written.
    }
  }

  /// Fixes the current round's homes when they are not recorded yet, or
  /// when the user changed what the round is made of (moved the saved
  /// home, or changed the Settings count). Changed cache answers and
  /// searches elsewhere never change a fixed round.
  Future<void> _maybeFixRound() async {
    final uid = _uid;
    final id = _roundId;
    final key = _homeKey;
    final search = _homeSearch;
    final lat = _savedLatitude;
    final lon = _savedLongitude;
    if (uid == null || id == null || !_roundKnown) return;
    if (key == null || search == null || lat == null || lon == null) return;
    if (key.latitude != lat || key.longitude != lon) return;
    if (search is OwnerArea && !search.isSettled) return;
    if (search.isUnavailable || _homeRecords.isEmpty || _savedRadius <= 0) {
      return;
    }

    final current = _round;
    List<GeoRecord> members;
    if (current == null) {
      members = _homeRecords.take(_savedRadius).toList();
    } else if (current.centerLatitude != null &&
        current.centerLongitude != null &&
        haversineMeters(
              lat,
              lon,
              current.centerLatitude!,
              current.centerLongitude!,
            ) >
            roundMoveMeters) {
      // A new saved home: its own nearest homes.
      members = _homeRecords.take(_savedRadius).toList();
    } else if (current.target != null && current.target != _savedRadius) {
      // A new Settings count: keep the round's homes, then add the
      // nearest others up to the new count.
      members = current.members.take(_savedRadius).toList();
      final have = {for (final m in members) m.id};
      for (final r in _homeRecords) {
        if (members.length >= _savedRadius) break;
        if (have.add(r.id)) members.add(r);
      }
    } else {
      return;
    }

    final next = PrayerRound(
      members: members,
      centerLatitude: lat,
      centerLongitude: lon,
      target: _savedRadius,
    );
    _round = _roundCache[id] = next;
    _rebuild();
    try {
      await _repository.saveRoundMembers(uid, id, next);
    } catch (_) {
      // Rules without prayer_rounds: fixed on this device for the session.
    }
  }

  /// The homes for the next round: exactly this round's homes (the same
  /// neighborhood every round; nothing is looked up).
  PrayerRound nextRound() {
    final current = _round;
    return PrayerRound(
      members: current?.members ?? _homeList(),
      centerLatitude: current?.centerLatitude ?? _savedLatitude,
      centerLongitude: current?.centerLongitude ?? _savedLongitude,
      target: current?.target ?? _savedRadius,
    );
  }

  /// Makes [round] known for [roundId] before its document is read back.
  void rememberRound(String roundId, PrayerRound round) {
    _roundCache[roundId] = round;
  }

  /// The homes of "my neighborhood": the round's fixed homes (with fresher
  /// details when loaded), otherwise the nearest homes around the saved
  /// home.
  List<GeoRecord> _homeList() {
    final round = _round;
    if (round == null) return _homeRecords.take(_savedRadius).toList();
    final fresh = {
      for (final r in _records) r.id: r,
      for (final r in _homeRecords) r.id: r,
    };
    return [for (final m in round.members) fresh[m.id] ?? m];
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
      _homeRecords = const [];
      homeUnavailable.value = false;
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
      final search = _search(key.latitude, key.longitude, key.rangeKm);
      await search.ensure(SearchRange.maxHomes);
      if (generation != _homeGeneration) return;
      _setHome(search, key);
      await _loadStatusesFor(_homeRecords.map((r) => r.id));
      if (generation != _homeGeneration) return;
      _rebuild();
      await _maybeFixRound();
    } catch (_) {
      // The Prayer List keeps its previous neighborhood; Home shows errors.
    }
  }

  void _setHome(
    AreaSearch search,
    ({double latitude, double longitude, double rangeKm})? key,
  ) {
    _homeSearch = search;
    _homeRecords = search.records;
    _rememberOwners(_homeRecords);
    if (search is OwnerOverlayArea) _rememberOwners(search.owners.records);
    _homeIds = {for (final r in _homeRecords) r.id};
    homeUnavailable.value = search.isUnavailable;
    homeSourceNote.value = search is OwnerArea ? search.sourceNote : null;
    _homeKey = key;
  }

  /// A nearest-first search around a point: the Overture cells when
  /// `FeatureFlags.useCellHouseholds` is on (Settings range not used),
  /// otherwise the `households` collection within [radiusKm].
  AreaSearch _search(double latitude, double longitude, double radiusKm) {
    if (FeatureFlags.useCellHouseholds) {
      return _repository.nearestArea(latitude: latitude, longitude: longitude);
    }
    return GeoSearchArea(
      _repository.geoSearch(
        latitude: latitude,
        longitude: longitude,
        radiusKm: radiusKm,
      ),
    );
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
    _homeRecords = const [];
    _homeIds = const {};
    areaUnavailable.value = false;
    homeUnavailable.value = false;
    homeSourceNote.value = null;
    _homeKey = null;
    _viewSearch = null;
    _homeSearch = null;
    areaComplete.value = false;
    isLoadingArea.value = false;
    center.value = null;
    rangeMeters.value = null;
    cycleStartedAt.value = null;
    _statuses.clear();
    _owners.clear();
    _secondOwners.clear();
    _statusFetched.clear();
    statusCounts.clear();
    _records = const [];
    households.clear();
    areaHouseholds.clear();
    homeHouseholds.clear();
    trackedHouseholds.clear();
    prayedCount.value = 0;
    visitedCount.value = 0;
    prayersOffered.value = 0;
    _prayerEvents = 0;
    _round = null;
    _roundId = null;
    _roundKnown = false;
    _roundCache.clear();
  }

  Future<void> refreshHouseholds() async {
    final latitude = _latitude;
    final longitude = _longitude;
    if (_uid == null || latitude == null || longitude == null) {
      _records = const [];
      areaUnavailable.value = false;
      _rebuild();
      return;
    }

    final generation = ++_loadGeneration;
    _areaTarget = 0;
    isLoadingArea.value = false;
    isLoading.value = true;
    try {
      final search = _search(latitude, longitude, _loadedRangeKm);
      // Enough for the largest Home count; Neighborhood reads more on scroll.
      await search.ensure(SearchRange.maxHomes);
      if (generation != _loadGeneration) return;
      _viewSearch = search;
      _publishArea(search);
      if (_viewIsHome) {
        _setHome(search, _currentHomeKey);
        _homeGeneration++;
      }
      await _loadStatusesFor(_records.map((r) => r.id));
      if (generation != _loadGeneration) return;
      _rebuild();
      if (_viewIsHome) await _maybeFixRound();
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

  /// Owners that came with the records (Melissa-first neighborhood), so
  /// Prayer List and Follow-up keep the name for homes no longer on screen.
  void _rememberOwners(List<GeoRecord> records) {
    for (final r in records) {
      final name = r.ownerName;
      if (name != null) _owners.putIfAbsent(r.id, () => name);
      final second = r.ownerSecondName;
      if (second != null) _secondOwners.putIfAbsent(r.id, () => second);
    }
  }

  void _publishArea(AreaSearch search) {
    _records = search.records;
    _rememberOwners(_records);
    if (search is OwnerOverlayArea) _rememberOwners(search.owners.records);
    areaSourceNote.value = search is OwnerArea ? search.sourceNote : null;
    areaComplete.value = search.isComplete;
    areaUnavailable.value = search.isUnavailable;
    // Cells have no fixed range: show how far the households found reach.
    rangeMeters.value = search.extentMeters ?? _rangeKm * 1000;
  }

  /// Reads further out until at least [count] households around the current
  /// center are known (Neighborhood paging). A request made while a read is
  /// running raises its target instead of starting another; reads for an
  /// area no longer on screen are dropped.
  Future<void> loadMoreArea(int count) async {
    if (count > _areaTarget) _areaTarget = count;
    final search = _viewSearch;
    if (search == null || search.isComplete || isLoadingArea.value) return;
    if (search.records.length >= _areaTarget) return;
    final generation = _loadGeneration;
    isLoadingArea.value = true;
    try {
      while (!search.isComplete && search.records.length < _areaTarget) {
        await search.ensure(_areaTarget);
        if (generation != _loadGeneration || search != _viewSearch) return;
        _publishArea(search);
        await _loadStatusesFor(_records.map((r) => r.id));
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
    final round = _round;
    if (round != null) return round.contains(id);
    if (_homeIds.contains(id)) return true;
    final search = _homeSearch;
    if (search == null) return null;
    return search.contains(id);
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

  Future<void> _loadOwnerNames(String uid) async {
    try {
      final owners = await _repository.fetchOwnerNames(uid);
      if (uid != _uid || owners.isEmpty) return;
      owners.forEach((id, name) => _owners.putIfAbsent(id, () => name));
      _rebuild();
    } catch (_) {
      // Names appear again when a home is checked.
    }
  }

  /// The recorded owner of [householdId] from an address check just made
  /// (null removes it); updates every list showing the home.
  void setOwnerName(String householdId, String? name) {
    final clean = HouseholdModel.cleanName(name);
    if (_owners[householdId] == clean) return;
    if (clean == null) {
      _owners.remove(householdId);
    } else {
      _owners[householdId] = clean;
    }
    _rebuild();
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
    try {
      final events = await _repository.countPrayerEvents(uid);
      if (uid != _uid) return;
      _prayerEvents = events;
      _publishCounts();
    } catch (_) {
      // Rules without prayer_log: homes prayed for stand in.
    }
  }

  void _publishCounts() {
    prayedCount.value = statusCounts['isPrayed'] ?? 0;
    visitedCount.value = statusCounts['isVisited'] ?? 0;
    prayersOffered.value = math.max(_prayerEvents, prayedCount.value);
  }

  /// Adds [delta] prayer events (a prayer saved or undone on this device).
  void _countPrayerEvent(int delta) {
    _prayerEvents = math.max(0, _prayerEvents + delta);
    _publishCounts();
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
    final nameChanged =
        updated.residentName !=
        (current?.residentName ??
            HouseholdModel.cleanName(previous?['residentName']));

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
    if (nameChanged) {
      final name = updated.residentName;
      if (name == null) {
        next.remove('residentName');
      } else {
        next['residentName'] = name;
      }
    }
    next['updatedAt'] = DateTime.now();
    _statuses[updated.id] = next;
    final eventDelta = becamePrayed
        ? 1
        : (!updated.isPrayed && wasPrayedInCycle ? -1 : 0);
    _countChange(previous, next);
    if (eventDelta != 0) _countPrayerEvent(eventDelta);
    _rebuild();

    try {
      final write = _repository.saveStatus(
        uid: uid,
        household: updated,
        wasPrayed: wasPrayedInCycle,
        nameChanged: nameChanged,
        roundId: FirestorePaths.roundId(cycleStartedAt.value),
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
      if (eventDelta != 0) _countPrayerEvent(-eventDelta);
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
    return a['notes'] == b['notes'] &&
        a['followUpDate'] == b['followUpDate'] &&
        a['residentName'] == b['residentName'];
  }

  List<HouseholdModel> _fromRecords(List<GeoRecord> records) {
    final cycleStart = cycleStartedAt.value;
    return [
      for (var i = 0; i < records.length; i++)
        HouseholdModel.fromRecord(
          record: records[i],
          status: _statuses[records[i].id],
          number: i + 1,
          cycleStart: cycleStart,
        ).copyWith(
          ownerName: _owners[records[i].id],
          ownerSecondName: _secondOwners[records[i].id],
        ),
    ];
  }

  void _rebuild() {
    final area = _fromRecords(_records);
    foundInRange.value = area.length;
    // Nearest first, so the count keeps the closest homes.
    households.assignAll(area.take(_radiusHomes));
    areaHouseholds.assignAll(area);

    final home = _fromRecords(_homeList());
    homeHouseholds.assignAll(home);

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
          ).copyWith(
            ownerName: _owners[entry.key],
            ownerSecondName: _secondOwners[entry.key],
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
              'Follow-up with ${household.displayName} (${household.address}) on ${household.followUpDate ?? defaultFollowUpDate()}.',
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
