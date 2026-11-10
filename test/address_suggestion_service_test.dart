import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gps_cielo/core/services/address_suggestion_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Map<String, Object?> feature(
  Map<String, Object?> properties, {
  double lon = -74.04,
  double lat = 40.88,
}) {
  return {
    'type': 'Feature',
    'geometry': {
      'type': 'Point',
      'coordinates': [lon, lat],
    },
    'properties': properties,
  };
}

http.Response geoJson(List<Map<String, Object?>> features) => http.Response(
  jsonEncode({'type': 'FeatureCollection', 'features': features}),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

/// Records calls and returns canned results.
class FakeProvider implements AddressSearchProvider {
  final List<String> queries = [];
  Completer<List<AddressSuggestion>>? pending;
  Object? error;

  @override
  String get attribution => 'test attribution';

  @override
  Future<List<AddressSuggestion>> search(
    String query, {
    double? nearLatitude,
    double? nearLongitude,
    int limit = 5,
  }) {
    queries.add(query);
    if (error != null) return Future.error(error!);
    final completer = pending;
    if (completer != null) return completer.future;
    return Future.value([
      AddressSuggestion(
        title: query,
        subtitle: 'Dhaka, Bangladesh',
        latitude: 23.75,
        longitude: 90.38,
      ),
    ]);
  }

  @override
  Future<AddressSuggestion?> reverse(double latitude, double longitude) async {
    return null;
  }
}

void main() {
  group('PhotonAddressProvider.parse', () {
    test('formats a US house address with state abbreviation', () {
      final results = PhotonAddressProvider.parse({
        'features': [
          feature(
            {
              'type': 'house',
              'housenumber': '168',
              'street': 'Main Street',
              'city': 'Hackensack',
              'state': 'New Jersey',
              'postcode': '07601',
            },
            lon: -74.043,
            lat: 40.884,
          ),
        ],
      }, query: '168 Main');

      expect(results, hasLength(1));
      expect(
        results.first.fullAddress,
        '168 Main Street, Hackensack, NJ 07601',
      );
      // GeoJSON is [longitude, latitude].
      expect(results.first.latitude, 40.884);
      expect(results.first.longitude, -74.043);
    });

    test('formats Bangladesh district, region, postcode and country', () {
      final results = PhotonAddressProvider.parse({
        'features': [
          feature(
            {
              'type': 'district',
              'name': 'Dhanmondi',
              'city': 'Dhaka',
              'county': 'Dhaka Metropolitan',
              'state': 'Dhaka Division',
              'country': 'Bangladesh',
              'postcode': '1205',
              'countrycode': 'BD',
            },
            lon: 90.3745866,
            lat: 23.7479124,
          ),
        ],
      }, query: 'Dhanmondi');

      expect(
        results.single.fullAddress,
        'Dhanmondi, Dhaka, Dhaka Division 1205, Bangladesh',
      );
      expect(results.single.latitude, 23.7479124);
      expect(results.single.longitude, 90.3745866);
    });

    test('a named place keeps its street address in the subtitle', () {
      final results = PhotonAddressProvider.parse({
        'features': [
          feature({
            'type': 'house',
            'name': 'Dhanmondi 27 Bus stop',
            'street': 'Mirpur Road',
            'district': 'Sobhanbag',
            'city': 'Dhaka',
            'country': 'Bangladesh',
          }),
        ],
      }, query: 'Road 27 Dhanmondi');

      expect(results.single.title, 'Dhanmondi 27 Bus stop');
      expect(
        results.single.subtitle,
        'Mirpur Road, Sobhanbag, Dhaka, Bangladesh',
      );
    });

    test('keeps the typed house number on street-only results', () {
      final results = PhotonAddressProvider.parse({
        'features': [
          feature({
            'type': 'street',
            'name': 'Main Street',
            'city': 'Hackensack',
            'state': 'New Jersey',
            'postcode': '07661',
          }),
        ],
      }, query: '168 Main St Hackensack');

      expect(results.single.title, '168 Main Street');
    });

    test('reverse results never use a nearby place name or invent numbers', () {
      final results = PhotonAddressProvider.parse(
        {
          'features': [
            feature({
              'type': 'house',
              'name': 'Darul Ihsan University',
              'street': 'Dhanmondi 9A',
              'district': 'Dhanmondi',
              'city': 'Dhaka',
              'country': 'Bangladesh',
            }),
          ],
        },
        query: '',
        reverse: true,
      );

      expect(
        results.single.fullAddress,
        'Dhanmondi 9A, Dhanmondi, Dhaka, Bangladesh',
      );
    });

    test('removes duplicates and respects the limit', () {
      final street = feature({
        'type': 'street',
        'name': 'Main Street',
        'city': 'Hackensack',
        'state': 'New Jersey',
      });
      final results = PhotonAddressProvider.parse(
        {
          'features': [
            street,
            street,
            feature({
              'type': 'city',
              'name': 'Paterson',
              'state': 'New Jersey',
            }),
          ],
        },
        query: 'Main',
        limit: 2,
      );

      expect(results.map((r) => r.fullAddress), [
        'Main Street, Hackensack, NJ',
        'Paterson, NJ',
      ]);
    });

    test('ignores malformed responses', () {
      expect(PhotonAddressProvider.parse(null, query: 'x'), isEmpty);
      expect(
        PhotonAddressProvider.parse({
          'features': [
            {'properties': {}},
            {
              'geometry': {
                'coordinates': ['a', 'b'],
              },
              'properties': {'name': 'Bad'},
            },
          ],
        }, query: 'x'),
        isEmpty,
      );
    });
  });

  group('PhotonAddressProvider HTTP', () {
    test('sends only the query, bias point and options', () async {
      late Uri requested;
      late Map<String, String> headers;
      final provider = PhotonAddressProvider(
        client: MockClient((request) async {
          requested = request.url;
          headers = request.headers;
          return geoJson([
            feature({'type': 'city', 'name': 'Dhaka'}, lon: 90.4, lat: 23.8),
          ]);
        }),
      );

      final results = await provider.search(
        'Dhaka',
        nearLatitude: 23.7,
        nearLongitude: 90.3,
      );

      expect(results.single.title, 'Dhaka');
      expect(requested.host, 'photon.komoot.io');
      expect(requested.path, '/api/');
      expect(requested.queryParameters['q'], 'Dhaka');
      expect(requested.queryParameters['lat'], '23.7');
      expect(requested.queryParameters['lon'], '90.3');
      expect(requested.queryParametersAll['layer'], contains('district'));
      expect(requested.queryParameters.keys, isNot(contains('key')));
      expect(
        headers.keys.map((k) => k.toLowerCase()),
        isNot(contains('authorization')),
      );
    });

    test('a custom base URL supports a self-hosted instance', () async {
      late Uri requested;
      final provider = PhotonAddressProvider(
        baseUri: Uri.parse('https://geo.example.org/photon/'),
        client: MockClient((request) async {
          requested = request.url;
          return geoJson([]);
        }),
      );
      await provider.reverse(23.7, 90.3);
      expect(
        requested.toString(),
        startsWith('https://geo.example.org/photon/reverse?lat=23.7'),
      );
    });

    test('HTTP 429 is reported as rate limited', () async {
      final provider = PhotonAddressProvider(
        client: MockClient((_) async => http.Response('slow down', 429)),
      );
      await expectLater(
        provider.search('Dhaka'),
        throwsA(
          isA<AddressSearchException>().having(
            (e) => e.rateLimited,
            'rateLimited',
            isTrue,
          ),
        ),
      );
    });

    test('server errors and bad JSON become AddressSearchException', () async {
      final failing = PhotonAddressProvider(
        client: MockClient((_) async => http.Response('oops', 500)),
      );
      await expectLater(
        failing.search('Dhaka'),
        throwsA(isA<AddressSearchException>()),
      );

      final garbage = PhotonAddressProvider(
        client: MockClient((_) async => http.Response('<html>', 200)),
      );
      await expectLater(
        garbage.search('Dhaka'),
        throwsA(isA<AddressSearchException>()),
      );
    });

    test('a slow server times out', () async {
      final provider = PhotonAddressProvider(
        timeout: const Duration(milliseconds: 20),
        client: MockClient((_) => Completer<http.Response>().future),
      );
      await expectLater(
        provider.search('Dhaka'),
        throwsA(
          isA<AddressSearchException>().having(
            (e) => e.message,
            'message',
            contains('timed out'),
          ),
        ),
      );
    });

    test('reverse returns null when nothing is mapped nearby', () async {
      final provider = PhotonAddressProvider(
        client: MockClient((_) async => geoJson([])),
      );
      expect(await provider.reverse(21.0, 92.0), isNull);
    });
  });

  group('AddressSuggestionService', () {
    AddressSuggestionService service(FakeProvider provider) =>
        AddressSuggestionService(
          provider: provider,
          minInterval: Duration.zero,
        );

    test('needs at least three characters', () async {
      final provider = FakeProvider();
      final s = service(provider);
      expect(await s.search('Dh'), isEmpty);
      expect(await s.search('  Dh  '), isEmpty);
      expect(provider.queries, isEmpty);
      expect(await s.search('Dha'), hasLength(1));
      expect(provider.queries, ['Dha']);
    });

    test('caches results and normalises whitespace and case', () async {
      final provider = FakeProvider();
      final s = service(provider);
      await s.search('Dhanmondi  Road');
      await s.search('dhanmondi road');
      expect(provider.queries, hasLength(1));
    });

    test('identical concurrent queries share one request', () async {
      final provider = FakeProvider()
        ..pending = Completer<List<AddressSuggestion>>();
      final s = service(provider);
      final a = s.search('Mirpur');
      final b = s.search('Mirpur');
      await Future<void>.delayed(Duration.zero);
      provider.pending!.complete(const []);
      await Future.wait([a, b]);
      expect(provider.queries, ['Mirpur']);
    });

    test('errors propagate so the UI can show them', () async {
      final provider = FakeProvider()
        ..error = const AddressSearchException('offline');
      await expectLater(
        service(provider).search('Gulshan'),
        throwsA(isA<AddressSearchException>()),
      );
    });

    test('spaces network requests by the minimum interval', () async {
      final provider = FakeProvider();
      final s = AddressSuggestionService(
        provider: provider,
        minInterval: const Duration(milliseconds: 80),
      );
      final watch = Stopwatch()..start();
      await s.search('Uttara');
      await s.search('Uttara Sector');
      expect(watch.elapsedMilliseconds, greaterThanOrEqualTo(70));
      expect(provider.queries, hasLength(2));
    });
  });
}
