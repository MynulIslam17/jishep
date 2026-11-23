import 'dart:math' as math;

import 'package:cloud_functions/cloud_functions.dart';
import 'package:gps_cielo/core/data/area_search.dart';
import 'package:gps_cielo/core/data/geo_record.dart';
import 'package:gps_cielo/core/utils/geohash.dart';

/// What the `discoverOwners` Cloud Function reported for an area.
class OwnerDiscoveryResult {
  const OwnerDiscoveryResult({
    required this.records,
    required this.full,
    required this.cached,
    this.completeness = 'complete',
    this.pending = false,
    this.stats = const {},
  });

  /// Named residential properties, nearest first (never placeholders).
  final List<GeoRecord> records;

  /// True when the requested number of named homes was found.
  final bool full;

  /// True when the server answered from its stored result (no credits).
  final bool cached;

  /// How sure the server is that these are the nearest homes:
  /// `complete` (proven nearest, or every home in range), `partial` (stored
  /// homes; closer ones may exist), `empty` (no homes in range), `expired`
  /// or `unknown` (nothing usable stored), `legacy` (older stored result).
  final String completeness;

  /// Another request is still looking up this area.
  final bool pending;

  /// Nothing stored for this area (or only expired records).
  bool get nothingStored =>
      records.isEmpty &&
      (completeness == 'unknown' || completeness == 'expired');

  /// Server counts: addressesFound, lookups, named, nonResidential, …
  final Map<String, int> stats;
}

/// Calls the `discoverOwners` Cloud Function: Melissa Reverse GeoCoder +
/// Property on the server (keys never reach the app).
class OwnerDiscoveryService {
  OwnerDiscoveryService({
    Future<Map<Object?, Object?>> Function(Map<String, Object?> data)? call,
  }) : _call = call ?? _callFunction;

  final Future<Map<Object?, Object?>> Function(Map<String, Object?> data) _call;

  static Future<Map<Object?, Object?>> _callFunction(
    Map<String, Object?> data,
  ) async {
    final result = await FirebaseFunctions.instanceFor(region: 'us-central1')
        .httpsCallable(
          'discoverOwners',
          // Up to ~80 property lookups on the server.
          options: HttpsCallableOptions(timeout: const Duration(seconds: 150)),
        )
        .call<Map<Object?, Object?>>(data);
    return result.data;
  }

  /// Up to [target] named residential properties nearest the point.
  Future<OwnerDiscoveryResult> discover({
    required double latitude,
    required double longitude,
    int target = 50,
  }) async {
    final data = await _call({
      'latitude': latitude,
      'longitude': longitude,
      'target': target,
    });
    final list = data['records'];
    final stats = data['stats'];
    return OwnerDiscoveryResult(
      records: [
        if (list is List)
          for (final r in list)
            if (r is Map) ?recordFrom(r),
      ],
      full: data['coverage'] == 'full',
      cached: data['cached'] == true,
      completeness: data['completeness']?.toString() ?? 'complete',
      pending: data['pending'] == true,
      stats: {
        if (stats is Map)
          for (final e in stats.entries)
            if (e.value is int) e.key.toString(): e.value as int,
      },
    );
  }

  /// One backend record as a [GeoRecord] with its recorded owner, or null
  /// when it is invalid or has no owner name (never shown unnamed).
  static GeoRecord? recordFrom(Map<Object?, Object?> r) {
    final lat = r['latitude'];
    final lon = r['longitude'];
    final id = r['id']?.toString() ?? '';
    final line = r['line']?.toString().trim() ?? '';
    final owner = r['owner'];
    final name = owner is Map ? owner['name']?.toString().trim() ?? '' : '';
    final second = owner is Map
        ? owner['secondName']?.toString().trim() ?? ''
        : '';
    if (lat is! num ||
        lon is! num ||
        !id.startsWith('mel:') ||
        line.isEmpty ||
        name.isEmpty) {
      return null;
    }
    String? part(String k) {
      final v = r[k]?.toString().trim() ?? '';
      return v.isEmpty ? null : v;
    }

    final classification = r['classification'];
    final label = classification is Map
        ? classification['label']?.toString().trim()
        : null;
    final cityState = [
      part('city')?.toUpperCase(),
      part('state')?.toUpperCase(),
    ].whereType<String>().join(', ');
    return GeoRecord(
      id: id,
      latitude: lat.toDouble(),
      longitude: lon.toDouble(),
      geohash: Geohash.encode(lat.toDouble(), lon.toDouble(), 9),
      address: line.toUpperCase(),
      cityStateZip: [
        if (cityState.isNotEmpty) cityState,
        ?part('zip'),
      ].join(' '),
      ownerName: name,
      ownerSecondName: second.isEmpty ? null : second,
      ownerIsEntity:
          owner is Map &&
          (owner['isCompany'] == true || owner['isTrust'] == true),
      propertyClass: label == null || label.isEmpty ? null : label,
    );
  }

  /// A reason the server gives on purpose (switched off, limits, nothing
  /// stored), as opposed to a passing failure.
  static bool isKnownReason(String? reason) => const {
    'user_daily_limit',
    'app_daily_limit',
    'out_of_credits',
    'owner_discovery_disabled',
    'owner_names_disabled',
    'owner_cache_disabled',
    'unknown',
    'expired',
    'outside_us',
  }.contains(reason);

  /// User-facing text for a backend error reason.
  static String messageFor(String? reason) => switch (reason) {
    'user_daily_limit' =>
      "You've looked up new areas enough times today. Try again tomorrow.",
    'app_daily_limit' ||
    'out_of_credits' => 'Property owner lookups are paused for now.',
    'owner_discovery_disabled' ||
    'owner_names_disabled' => 'Property owner lookups are not turned on yet.',
    'unknown' => 'Property owner records are not available for this area yet.',
    'expired' => 'Stored property owner records for this area have expired.',
    'empty' => 'No homes with a recorded property owner were found here.',
    'partial' ||
    'legacy' ||
    'complete' => 'No stored property owner records near this point yet.',
    'outside_us' => 'Homes are available only in the United States.',
    _ => "Couldn't look up property owners right now.",
  };
}

/// The Melissa-first neighborhood (app build flag `MELISSA_OWNERS`): only
/// residential properties with a recorded owner, nearest first, as many as
/// are really stored or found (up to [target]); never invented, never
/// padded.
///
/// Melissa only: Overture addresses are NEVER shown in their place. When
/// the server has no owner records for the area (nothing stored, lookups
/// switched off, limits, no network), the area is empty and
/// [unavailableReason] says why (shown on Home, Prayer List and
/// Neighborhood).
class OwnerArea implements AreaSearch {
  OwnerArea({
    required this.service,
    required this.latitude,
    required this.longitude,
    this.target = 50,
    this.pendingRetries = 2,
    this.retryDelay = const Duration(seconds: 3),
  });

  final int pendingRetries;
  final Duration retryDelay;
  final OwnerDiscoveryService service;
  final double latitude;
  final double longitude;
  final int target;

  List<GeoRecord> _named = const [];
  bool _complete = false;
  Future<void>? _loading;

  /// Why no owner records are shown (user-facing), or null.
  String? unavailableReason;

  /// The server's result, once loaded.
  OwnerDiscoveryResult? result;

  /// The answer failed for a passing reason (network, server error).
  bool _transientFailure = false;

  /// The list will not change on its own: loaded, not still being looked up
  /// elsewhere, and not a passing error. Only a settled list may fix a
  /// prayer round's homes.
  bool get isSettled =>
      (result != null || unavailableReason != null) &&
      result?.pending != true &&
      !_transientFailure;

  /// One line for the screens: where the homes come from, how complete the
  /// list is, or why it is empty.
  /// A short line for the neighborhood header, only when something needs
  /// saying (no homes here, or still looking). Normal results show none:
  /// the count is already on screen.
  String? get sourceNote {
    final reason = unavailableReason;
    if (reason != null) return reason;
    if (result?.pending ?? false) return 'Still looking up this area';
    return null;
  }

  @override
  List<GeoRecord> get records => _named;

  @override
  bool get isComplete => _complete;

  @override
  bool get isUnavailable => unavailableReason != null && _named.isEmpty;

  @override
  double? get extentMeters {
    if (_named.isEmpty) return null;
    return _named
        .map(
          (r) => haversineMeters(latitude, longitude, r.latitude, r.longitude),
        )
        .reduce(math.max);
  }

  @override
  bool? contains(String id) {
    return _complete ? _named.any((r) => r.id == id) : null;
  }

  @override
  Future<void> ensure(int count) {
    if (_complete) return Future.value();
    return _loading ??= _load().whenComplete(() => _loading = null);
  }

  Future<void> _load() async {
    try {
      var r = await service.discover(
        latitude: latitude,
        longitude: longitude,
        target: target,
      );
      // Someone else is looking this area up: read their result shortly
      // instead of starting another lookup.
      for (var i = 0; r.pending && i < pendingRetries; i++) {
        await Future<void>.delayed(retryDelay);
        r = await service.discover(
          latitude: latitude,
          longitude: longitude,
          target: target,
        );
      }
      result = r;
      _named = r.records;
      if (r.records.isEmpty && !r.pending) {
        unavailableReason = OwnerDiscoveryService.messageFor(r.completeness);
      }
    } on FirebaseFunctionsException catch (e) {
      unavailableReason = OwnerDiscoveryService.messageFor(e.message);
      _transientFailure = !OwnerDiscoveryService.isKnownReason(e.message);
    } catch (_) {
      _transientFailure = true;
      unavailableReason = OwnerDiscoveryService.messageFor(null);
    }
    // A passing failure may be retried (pull to refresh reloads the area).
    _complete = true;
  }
}

/// The normal neighborhood (Overture homes, same ids, same rounds and
/// prayer history) with the recorded owner added to every home that has a
/// stored owner record at the same street address (within [maxMeters]).
/// Homes without one keep their address as the title; an area with no
/// stored owner records looks exactly like before. Owner records never add
/// or replace homes, and nothing is ever guessed: the street address must
/// match exactly (after spelling out common abbreviations).
class OwnerOverlayArea implements AreaSearch {
  OwnerOverlayArea({required this.inner, required this.owners});

  /// The homes (Overture cells, or gap-filled).
  final AreaSearch inner;

  /// Stored owner records around the same point (`discoverOwners`).
  final OwnerArea owners;

  static const double maxMeters = 250;

  List<GeoRecord>? _cache;
  List<GeoRecord>? _cacheInner;
  List<GeoRecord>? _cacheOwners;

  static const Map<String, String> _suffixes = {
    'AVENUE': 'AVE',
    'STREET': 'ST',
    'DRIVE': 'DR',
    'ROAD': 'RD',
    'COURT': 'CT',
    'PLACE': 'PL',
    'LANE': 'LN',
    'BOULEVARD': 'BLVD',
    'CIRCLE': 'CIR',
    'TERRACE': 'TER',
    'PARKWAY': 'PKWY',
    'HIGHWAY': 'HWY',
    'NORTH': 'N',
    'SOUTH': 'S',
    'EAST': 'E',
    'WEST': 'W',
  };

  /// "724 Cardona Avenue" and "724 CARDONA AVE" give the same key.
  static String addressKey(String address) => address
      .toUpperCase()
      .replaceAll(RegExp(r'[^A-Z0-9 ]'), ' ')
      .split(' ')
      .where((w) => w.isNotEmpty)
      .map((w) => _suffixes[w] ?? w)
      .join(' ');

  /// [homes] with the owner of a matching record in [named] added.
  static List<GeoRecord> overlay(List<GeoRecord> homes, List<GeoRecord> named) {
    if (named.isEmpty) return homes;
    final byKey = <String, List<GeoRecord>>{};
    for (final r in named) {
      if (r.ownerName == null) continue;
      byKey.putIfAbsent(addressKey(r.address), () => []).add(r);
    }
    return [
      for (final h in homes)
        if (h.ownerName != null)
          h
        else
          _withOwner(h, byKey[addressKey(h.address)]),
    ];
  }

  static GeoRecord _withOwner(GeoRecord h, List<GeoRecord>? candidates) {
    if (candidates == null) return h;
    GeoRecord? best;
    var bestMeters = maxMeters;
    for (final c in candidates) {
      final m = haversineMeters(
        h.latitude,
        h.longitude,
        c.latitude,
        c.longitude,
      );
      if (m <= bestMeters) {
        best = c;
        bestMeters = m;
      }
    }
    if (best == null) return h;
    return GeoRecord(
      id: h.id,
      latitude: h.latitude,
      longitude: h.longitude,
      geohash: h.geohash,
      address: h.address,
      cityStateZip: h.cityStateZip,
      ownerName: best.ownerName,
      ownerSecondName: best.ownerSecondName,
      ownerIsEntity: best.ownerIsEntity,
      propertyClass: best.propertyClass,
    );
  }

  @override
  List<GeoRecord> get records {
    final homes = inner.records;
    final named = owners.records;
    if (!identical(homes, _cacheInner) || !identical(named, _cacheOwners)) {
      _cacheInner = homes;
      _cacheOwners = named;
      _cache = overlay(homes, named);
    }
    return _cache!;
  }

  /// Owner records loaded (or known to be unavailable) as well as homes.
  @override
  bool get isComplete => inner.isComplete && owners.isComplete;

  @override
  bool get isUnavailable => inner.isUnavailable;

  @override
  double? get extentMeters => inner.extentMeters;

  @override
  bool? contains(String id) => inner.contains(id);

  /// Owner lookups never block or fail the homes: [OwnerArea] catches its
  /// own errors (switched off, nothing stored, offline).
  @override
  Future<void> ensure(int count) =>
      Future.wait([inner.ensure(count), owners.ensure(count)]);
}
