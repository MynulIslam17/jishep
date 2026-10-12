import 'dart:convert';

import 'package:gps_cielo/core/services/location_service.dart';
import 'package:gps_cielo/core/utils/api_debug_log.dart';
import 'package:http/http.dart' as http;

class AddressSuggestion {
  /// Street line, e.g. "168 Main Street".
  final String title;

  /// City, state and ZIP, e.g. "Hackensack, NJ 07601".
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

  ResolvedLocation toResolvedLocation() {
    return ResolvedLocation(
      address: fullAddress,
      latitude: latitude,
      longitude: longitude,
    );
  }
}

/// Search-as-you-type address suggestions from Photon
/// (https://photon.komoot.io), a free OpenStreetMap geocoder that needs no API
/// key or billing account.
class AddressSuggestionService {
  final http.Client _client;

  AddressSuggestionService({http.Client? client})
      : _client = client ?? http.Client();

  static const int minQueryLength = 3;
  static const Duration _timeout = Duration(seconds: 6);
  static final RegExp _leadingHouseNumber = RegExp(r'^\s*(\d+[A-Za-z]?)\s+\S');

  final Map<String, List<AddressSuggestion>> _cache = {};

  /// Returns up to [limit] suggestions for [query], biased towards the given
  /// coordinates when provided. Network errors yield an empty list.
  Future<List<AddressSuggestion>> search(
    String query, {
    double? nearLatitude,
    double? nearLongitude,
    int limit = 5,
  }) async {
    final trimmed = query.trim();
    if (trimmed.length < minQueryLength) return const [];

    final cacheKey = '$trimmed|$nearLatitude|$nearLongitude';
    final cached = _cache[cacheKey];
    if (cached != null) return cached;

    try {
      return await ApiDebugLog.run(
        'AddressSuggestionService.search',
        () async {
          final uri = _buildUri(trimmed, nearLatitude, nearLongitude, limit);
          final response = await _client
              .get(
                uri,
                headers: const {
                  'User-Agent': 'GPSParaElCielo/1.0 (Flutter app)',
                },
              )
              .timeout(_timeout);
          if (response.statusCode != 200) {
            throw Exception('HTTP ${response.statusCode}');
          }

          final suggestions = parse(
            jsonDecode(utf8.decode(response.bodyBytes)),
            query: trimmed,
            limit: limit,
          );
          if (_cache.length > 50) _cache.clear();
          _cache[cacheKey] = suggestions;
          return suggestions;
        },
        details: trimmed,
      );
    } catch (_) {
      return const [];
    }
  }

  /// Builds the query manually because Photon expects `layer` repeated.
  Uri _buildUri(
    String query,
    double? latitude,
    double? longitude,
    int limit,
  ) {
    final params = <String>[
      'q=${Uri.encodeQueryComponent(query)}',
      'limit=${limit * 2}',
      'lang=en',
      if (latitude != null && longitude != null) ...[
        'lat=$latitude',
        'lon=$longitude',
      ],
      for (final layer in const ['house', 'street', 'city', 'locality'])
        'layer=$layer',
    ];
    return Uri.parse('https://photon.komoot.io/api/?${params.join('&')}');
  }

  /// Converts a Photon GeoJSON response into de-duplicated suggestions.
  ///
  /// OpenStreetMap often has streets without individual house numbers; when
  /// the user typed a house number it is kept on the street suggestion.
  static List<AddressSuggestion> parse(
    Object? json, {
    required String query,
    int limit = 5,
  }) {
    if (json is! Map || json['features'] is! List) return const [];

    final typedNumber = _leadingHouseNumber.firstMatch(query)?.group(1);
    final seen = <String>{};
    final results = <AddressSuggestion>[];

    for (final feature in json['features'] as List) {
      if (feature is! Map) continue;
      final props = feature['properties'];
      final coordinates = feature['geometry']?['coordinates'];
      if (props is! Map || coordinates is! List || coordinates.length < 2) {
        continue;
      }

      final type = props['type']?.toString();
      final name = props['name']?.toString();
      final street =
          props['street']?.toString() ?? (type == 'street' ? name : null);
      final houseNumber = props['housenumber']?.toString() ??
          (street != null ? typedNumber : null);

      final title = street != null
          ? [houseNumber, street].whereType<String>().join(' ')
          : (name ?? props['city']?.toString());
      if (title == null || title.isEmpty) continue;

      final stateZip = [
        _stateAbbreviation(props['state']?.toString()),
        props['postcode']?.toString(),
      ].whereType<String>().where((p) => p.isNotEmpty).join(' ');
      final city = props['city']?.toString() ??
          props['town']?.toString() ??
          props['village']?.toString();
      final subtitle = [
        if (city != null && city != title) city,
        if (stateZip.isNotEmpty) stateZip,
      ].join(', ');

      final suggestion = AddressSuggestion(
        title: title,
        subtitle: subtitle,
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
    'Alabama': 'AL', 'Alaska': 'AK', 'Arizona': 'AZ', 'Arkansas': 'AR',
    'California': 'CA', 'Colorado': 'CO', 'Connecticut': 'CT',
    'Delaware': 'DE', 'District of Columbia': 'DC', 'Florida': 'FL',
    'Georgia': 'GA', 'Hawaii': 'HI', 'Idaho': 'ID', 'Illinois': 'IL',
    'Indiana': 'IN', 'Iowa': 'IA', 'Kansas': 'KS', 'Kentucky': 'KY',
    'Louisiana': 'LA', 'Maine': 'ME', 'Maryland': 'MD',
    'Massachusetts': 'MA', 'Michigan': 'MI', 'Minnesota': 'MN',
    'Mississippi': 'MS', 'Missouri': 'MO', 'Montana': 'MT',
    'Nebraska': 'NE', 'Nevada': 'NV', 'New Hampshire': 'NH',
    'New Jersey': 'NJ', 'New Mexico': 'NM', 'New York': 'NY',
    'North Carolina': 'NC', 'North Dakota': 'ND', 'Ohio': 'OH',
    'Oklahoma': 'OK', 'Oregon': 'OR', 'Pennsylvania': 'PA',
    'Puerto Rico': 'PR', 'Rhode Island': 'RI', 'South Carolina': 'SC',
    'South Dakota': 'SD', 'Tennessee': 'TN', 'Texas': 'TX', 'Utah': 'UT',
    'Vermont': 'VT', 'Virginia': 'VA', 'Washington': 'WA',
    'West Virginia': 'WV', 'Wisconsin': 'WI', 'Wyoming': 'WY',
  };
}
