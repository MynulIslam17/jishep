import 'dart:async';
import 'dart:convert';

import 'package:gps_cielo/core/services/location_service.dart';
import 'package:http/http.dart' as http;

class AddressSuggestion {
  /// First line, e.g. "168 Main Street" or "Dhanmondi".
  final String title;

  /// Area, city, region, postal code and country,
  /// e.g. "Hackensack, NJ 07601" or "Dhaka, Dhaka Division 1205, Bangladesh".
  final String subtitle;
  final double latitude;
  final double longitude;

  const AddressSuggestion({
    required this.title,
    required this.subtitle,
    required this.latitude,
    required this.longitude,
  });

  String get fullAddress => subtitle.isEmpty ? title : '$title, $subtitle';

  ResolvedLocation toResolvedLocation({
    LocationSource source = LocationSource.search,
  }) {
    return ResolvedLocation(
      address: fullAddress,
      latitude: latitude,
      longitude: longitude,
      source: source,
    );
  }
}

/// A user-safe address search failure (network, timeout, rate limit).
class AddressSearchException implements Exception {
  final String message;

  /// The server asked us to slow down (HTTP 429).
  final bool rateLimited;

  const AddressSearchException(this.message, {this.rateLimited = false});

  @override
  String toString() => message;
}

/// A geocoding backend. Swap the implementation to move from the public
/// Photon server to a hosted or self-hosted instance.
abstract interface class AddressSearchProvider {
  /// Attribution that must be shown next to results.
  String get attribution;

  /// Forward search. Throws [AddressSearchException] on failure.
  Future<List<AddressSuggestion>> search(
    String query, {
    double? nearLatitude,
    double? nearLongitude,
    int limit,
  });

  /// Nearest mapped address for a point, or null when there is none.
  /// Throws [AddressSearchException] on failure.
  Future<AddressSuggestion?> reverse(double latitude, double longitude);
}

/// Photon (https://photon.komoot.io), a free OpenStreetMap geocoder that needs
/// no API key or billing account. Only the typed text and an optional bias
/// point are sent: never credentials, tokens or profile data.
class PhotonAddressProvider implements AddressSearchProvider {
  PhotonAddressProvider({
    http.Client? client,
    Uri? baseUri,
    this.language = 'en',
    this.timeout = const Duration(seconds: 8),
  }) : _client = client ?? http.Client(),
       _baseUri = baseUri ?? publicEndpoint;

  /// Public demo server. Fair use only; heavy traffic is throttled.
  static final Uri publicEndpoint = Uri.parse('https://photon.komoot.io/');

  static const Map<String, String> _headers = {
    'User-Agent': 'GPSParaElCielo/1.0 (Flutter app)',
    'Accept': 'application/json',
  };

  final http.Client _client;
  final Uri _baseUri;
  final String language;
  final Duration timeout;

  @override
  String get attribution => '© OpenStreetMap contributors · Search by Photon';

  @override
  Future<List<AddressSuggestion>> search(
    String query, {
    double? nearLatitude,
    double? nearLongitude,
    int limit = 5,
  }) async {
    final params = <String>[
      'q=${Uri.encodeQueryComponent(query)}',
      // Extra results leave room for de-duplication.
      'limit=${limit * 2}',
      'lang=$language',
      if (nearLatitude != null && nearLongitude != null) ...[
        'lat=$nearLatitude',
        'lon=$nearLongitude',
      ],
      // Photon expects `layer` repeated.
      for (final layer in const [
        'house',
        'street',
        'locality',
        'district',
        'city',
      ])
        'layer=$layer',
    ];
    final json = await _get('api/', params);
    return parse(json, query: query, limit: limit);
  }

  @override
  Future<AddressSuggestion?> reverse(double latitude, double longitude) async {
    final json = await _get('reverse', [
      'lat=$latitude',
      'lon=$longitude',
      'lang=$language',
      'limit=1',
    ]);
    final results = parse(json, query: '', limit: 1, reverse: true);
    return results.isEmpty ? null : results.first;
  }

  Future<Object?> _get(String path, List<String> params) async {
    final uri = _baseUri.resolve('$path?${params.join('&')}');
    final http.Response response;
    try {
      response = await _client.get(uri, headers: _headers).timeout(timeout);
    } on TimeoutException {
      throw const AddressSearchException(
        'Address search timed out. Check your connection or type the address.',
      );
    } catch (_) {
      throw const AddressSearchException(
        'Address search is unavailable. You can type the address manually.',
      );
    }

    if (response.statusCode == 429) {
      throw const AddressSearchException(
        'Address search is busy. Wait a moment or type the address manually.',
        rateLimited: true,
      );
    }
    if (response.statusCode != 200) {
      throw const AddressSearchException(
        'Address search is unavailable. You can type the address manually.',
      );
    }
    try {
      return jsonDecode(utf8.decode(response.bodyBytes));
    } catch (_) {
      throw const AddressSearchException(
        'Address search returned an unexpected response.',
      );
    }
  }

  static final RegExp _leadingHouseNumber = RegExp(r'^\s*(\d+[A-Za-z]?)\s+\S');

  /// Converts a Photon GeoJSON response into de-duplicated suggestions.
  ///
  /// GeoJSON coordinates are `[longitude, latitude]`. OpenStreetMap often has
  /// streets without individual house numbers; when the user typed a house
  /// number it is kept on the street suggestion (search only).
  ///
  /// With [reverse], names of nearby places (shops, schools) are not used as
  /// the address and no house number is invented.
  static List<AddressSuggestion> parse(
    Object? json, {
    required String query,
    int limit = 5,
    bool reverse = false,
  }) {
    if (json is! Map || json['features'] is! List) return const [];

    final typedNumber = reverse
        ? null
        : _leadingHouseNumber.firstMatch(query)?.group(1);
    final seen = <String>{};
    final results = <AddressSuggestion>[];

    for (final feature in json['features'] as List) {
      if (feature is! Map) continue;
      final props = feature['properties'];
      final geometry = feature['geometry'];
      final coordinates = geometry is Map ? geometry['coordinates'] : null;
      if (props is! Map ||
          coordinates is! List ||
          coordinates.length < 2 ||
          coordinates[0] is! num ||
          coordinates[1] is! num) {
        continue;
      }

      String? prop(String key) {
        final value = props[key]?.toString().trim();
        return value == null || value.isEmpty ? null : value;
      }

      final type = prop('type');
      final name = prop('name');
      final street = prop('street') ?? (type == 'street' ? name : null);
      final houseNumber =
          prop('housenumber') ?? (street != null ? typedNumber : null);
      final streetLine = street == null
          ? null
          : [houseNumber, street].whereType<String>().join(' ');

      // A named place that is not itself the street, e.g. "Bashundhara City".
      final placeName = name != null && name != street && type != 'street'
          ? name
          : null;
      final area = prop('district') ?? prop('locality');
      final city = prop('city') ?? prop('town') ?? prop('village');

      final String? title;
      final String? secondLine;
      if (reverse) {
        title = streetLine ?? area ?? city ?? placeName;
        secondLine = null;
      } else if (placeName != null && prop('housenumber') == null) {
        title = placeName;
        secondLine = streetLine;
      } else {
        title = streetLine ?? placeName;
        secondLine = null;
      }
      if (title == null || title.isEmpty) continue;

      final stateZip = [
        _stateAbbreviation(prop('state')),
        prop('postcode'),
      ].whereType<String>().join(' ');

      final parts = <String>[];
      void add(String? part) {
        if (part == null || part.isEmpty) return;
        if (part == title || parts.contains(part)) return;
        parts.add(part);
      }

      add(secondLine);
      add(area);
      add(city);
      add(stateZip);
      add(prop('country'));

      final suggestion = AddressSuggestion(
        title: title,
        subtitle: parts.join(', '),
        longitude: (coordinates[0] as num).toDouble(),
        latitude: (coordinates[1] as num).toDouble(),
      );
      if (!seen.add(suggestion.fullAddress.toLowerCase())) continue;

      results.add(suggestion);
      if (results.length >= limit) break;
    }
    return results;
  }

  static String? _stateAbbreviation(String? state) {
    if (state == null) return null;
    return _usStates[state] ?? state;
  }

  static const Map<String, String> _usStates = {
    'Alabama': 'AL',
    'Alaska': 'AK',
    'Arizona': 'AZ',
    'Arkansas': 'AR',
    'California': 'CA',
    'Colorado': 'CO',
    'Connecticut': 'CT',
    'Delaware': 'DE',
    'District of Columbia': 'DC',
    'Florida': 'FL',
    'Georgia': 'GA',
    'Hawaii': 'HI',
    'Idaho': 'ID',
    'Illinois': 'IL',
    'Indiana': 'IN',
    'Iowa': 'IA',
    'Kansas': 'KS',
    'Kentucky': 'KY',
    'Louisiana': 'LA',
    'Maine': 'ME',
    'Maryland': 'MD',
    'Massachusetts': 'MA',
    'Michigan': 'MI',
    'Minnesota': 'MN',
    'Mississippi': 'MS',
    'Missouri': 'MO',
    'Montana': 'MT',
    'Nebraska': 'NE',
    'Nevada': 'NV',
    'New Hampshire': 'NH',
    'New Jersey': 'NJ',
    'New Mexico': 'NM',
    'New York': 'NY',
    'North Carolina': 'NC',
    'North Dakota': 'ND',
    'Ohio': 'OH',
    'Oklahoma': 'OK',
    'Oregon': 'OR',
    'Pennsylvania': 'PA',
    'Puerto Rico': 'PR',
    'Rhode Island': 'RI',
    'South Carolina': 'SC',
    'South Dakota': 'SD',
    'Tennessee': 'TN',
    'Texas': 'TX',
    'Utah': 'UT',
    'Vermont': 'VT',
    'Virginia': 'VA',
    'Washington': 'WA',
    'West Virginia': 'WV',
    'Wisconsin': 'WI',
    'Wyoming': 'WY',
  };
}

/// Search-as-you-type address suggestions with caching, request
/// de-duplication and a minimum interval between network calls, so the free
/// public Photon server is used politely.
class AddressSuggestionService {
  AddressSuggestionService({
    AddressSearchProvider? provider,
    this.minInterval = const Duration(milliseconds: 1000),
    DateTime Function()? clock,
  }) : provider = provider ?? PhotonAddressProvider(),
       _clock = clock ?? DateTime.now;

  final AddressSearchProvider provider;

  /// Minimum time between two network requests.
  final Duration minInterval;
  final DateTime Function() _clock;

  static const int minQueryLength = 3;
  static const int maxResults = 5;
  static const Duration _rateLimitBackoff = Duration(seconds: 10);

  final Map<String, List<AddressSuggestion>> _cache = {};
  final Map<String, Future<List<AddressSuggestion>>> _inFlight = {};
  DateTime? _nextRequestAt;

  String get attribution => provider.attribution;

  /// Returns up to [limit] suggestions for [query], biased towards the given
  /// coordinates when provided. Queries shorter than [minQueryLength] return
  /// an empty list without a request. Throws [AddressSearchException].
  Future<List<AddressSuggestion>> search(
    String query, {
    double? nearLatitude,
    double? nearLongitude,
    int limit = maxResults,
  }) {
    final trimmed = query.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (trimmed.length < minQueryLength) return Future.value(const []);

    // ~1 km rounding keeps the cache useful while the bias point drifts.
    String round(double? v) => v == null ? '' : v.toStringAsFixed(2);
    final key =
        '${trimmed.toLowerCase()}|${round(nearLatitude)}|'
        '${round(nearLongitude)}|$limit';

    final cached = _cache[key];
    if (cached != null) return Future.value(cached);
    final pending = _inFlight[key];
    if (pending != null) return pending;

    final future =
        _throttled(
              () => provider.search(
                trimmed,
                nearLatitude: nearLatitude,
                nearLongitude: nearLongitude,
                limit: limit,
              ),
            )
            .then((results) {
              if (_cache.length >= 100) _cache.remove(_cache.keys.first);
              _cache[key] = results;
              return results;
            })
            .whenComplete(() {
              // Block body: returning the removed future would make it await itself.
              _inFlight.remove(key);
            });

    _inFlight[key] = future;
    return future;
  }

  /// Nearest mapped address for a GPS point, or null.
  Future<AddressSuggestion?> reverse(double latitude, double longitude) {
    return _throttled(() => provider.reverse(latitude, longitude));
  }

  Future<T> _throttled<T>(Future<T> Function() request) async {
    final now = _clock();
    final next = _nextRequestAt;
    final start = next != null && next.isAfter(now) ? next : now;
    _nextRequestAt = start.add(minInterval);
    if (start.isAfter(now)) {
      await Future<void>.delayed(start.difference(now));
    }
    try {
      return await request();
    } on AddressSearchException catch (e) {
      if (e.rateLimited) {
        _nextRequestAt = _clock().add(_rateLimitBackoff);
      }
      rethrow;
    }
  }
}
