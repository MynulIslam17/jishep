import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gps_cielo/core/data/area_search.dart';
import 'package:gps_cielo/core/data/geo_record.dart';
import 'package:gps_cielo/core/data/owner_discovery.dart';

class _Homes implements AreaSearch {
  _Homes(this.records);
  @override
  final List<GeoRecord> records;
  @override
  bool get isComplete => true;
  @override
  bool get isUnavailable => false;
  @override
  double? get extentMeters => 100;
  @override
  Future<void> ensure(int count) async {}
  @override
  bool? contains(String id) => records.any((r) => r.id == id);
}

GeoRecord _home(String id, String address, double lat, double lon) => GeoRecord(
  id: id,
  latitude: lat,
  longitude: lon,
  geohash: '',
  address: address,
  cityStateZip: 'CHULA VISTA, CA 91910',
);

Map<String, Object?> _owner(
  String id,
  String line,
  double lat,
  double lon,
  String name, [
  String? second,
]) => {
  'id': id,
  'latitude': lat,
  'longitude': lon,
  'line': line,
  'city': 'Chula Vista',
  'state': 'CA',
  'zip': '91910',
  'owner': {'name': name, 'secondName': ?second},
};

OwnerArea _owners(Future<Map<Object?, Object?>> Function() answer) => OwnerArea(
  service: OwnerDiscoveryService(call: (_) => answer()),
  latitude: 32.6435,
  longitude: -117.0185,
);

void main() {
  final homes = [
    _home('ov:1', '724 CARDONA AVE', 32.6435, -117.0185),
    _home('ov:2', '720 CARDONA AVE', 32.6436, -117.0186),
    _home('ov:3', '728 CARDONA AVE', 32.6437, -117.0187),
  ];

  test('adds the recorded owner to homes at the same address', () async {
    final area = OwnerOverlayArea(
      inner: _Homes(homes),
      owners: _owners(
        () async => {
          'coverage': 'full',
          'cached': true,
          'records': [
            _owner(
              'mel:1',
              '724 Cardona Avenue',
              32.6435,
              -117.0185,
              'Owner A',
              'Owner B',
            ),
            _owner('mel:2', '720 CARDONA AVE', 32.64361, -117.01861, 'Owner C'),
          ],
        },
      ),
    );
    await area.ensure(50);
    final r = area.records;
    // Same homes, same ids, same order: rounds and history keep working.
    expect(r.map((h) => h.id), ['ov:1', 'ov:2', 'ov:3']);
    expect(r[0].ownerName, 'Owner A');
    expect(r[0].ownerSecondName, 'Owner B');
    expect(r[0].address, '724 CARDONA AVE');
    expect(r[1].ownerName, 'Owner C');
    expect(r[2].ownerName, isNull); // no record: address stays the title
    expect(area.isComplete, isTrue);
  });

  test('never matches a different house number or a far-away twin', () async {
    final area = OwnerOverlayArea(
      inner: _Homes(homes),
      owners: _owners(
        () async => {
          'records': [
            _owner('mel:9', '726 CARDONA AVE', 32.6435, -117.0185, 'Owner X'),
            // Same street address in another town (~11 km away).
            _owner('mel:8', '728 CARDONA AVE', 32.7435, -117.0187, 'Owner Y'),
          ],
        },
      ),
    );
    await area.ensure(50);
    expect(area.records.every((h) => h.ownerName == null), isTrue);
  });

  test('owner names switched off or no records: homes unchanged', () async {
    for (final answer in <Future<Map<Object?, Object?>> Function()>[
      () async => throw FirebaseFunctionsException(
        message: 'owner_names_disabled',
        code: 'failed-precondition',
      ),
      () async => {'records': [], 'completeness': 'unknown'},
      () async => throw Exception('offline'),
    ]) {
      final area = OwnerOverlayArea(
        inner: _Homes(homes),
        owners: _owners(answer),
      );
      await area.ensure(50);
      expect(area.records, same(homes));
      expect(area.isUnavailable, isFalse);
      expect(area.isComplete, isTrue);
    }
  });

  test('address keys spell out common abbreviations', () {
    expect(
      OwnerOverlayArea.addressKey('1101 Camino Biscay, Street'),
      OwnerOverlayArea.addressKey('1101 CAMINO BISCAY ST'),
    );
    expect(
      OwnerOverlayArea.addressKey('705 Cardona Avenue'),
      isNot(OwnerOverlayArea.addressKey('705 Cardona Drive')),
    );
  });
}
