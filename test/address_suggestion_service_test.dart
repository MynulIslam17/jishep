import 'package:flutter_test/flutter_test.dart';
import 'package:gps_cielo/core/services/address_suggestion_service.dart';

Map<String, Object?> feature(
  Map<String, Object?> properties, {
  double lon = -74.04,
  double lat = 40.88,
}) {
  return {
    'geometry': {
      'coordinates': [lon, lat],
    },
    'properties': properties,
  };
}

void main() {
  group('AddressSuggestionService.parse', () {
    test('formats a house address with state abbreviation', () {
      final results = AddressSuggestionService.parse({
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
      expect(results.first.latitude, 40.884);
      expect(results.first.longitude, -74.043);
    });

    test('keeps the typed house number on street-only results', () {
      final results = AddressSuggestionService.parse({
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

    test('removes duplicates and respects the limit', () {
      final street = feature({
        'type': 'street',
        'name': 'Main Street',
        'city': 'Hackensack',
        'state': 'New Jersey',
      });
      final results = AddressSuggestionService.parse(
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
      expect(AddressSuggestionService.parse(null, query: 'x'), isEmpty);
      expect(
        AddressSuggestionService.parse({
          'features': [
            {'properties': {}},
          ],
        }, query: 'x'),
        isEmpty,
      );
    });
  });
}
