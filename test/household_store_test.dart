import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:gps_cielo/core/models/household_model.dart';
import 'package:gps_cielo/core/models/user_model.dart';
import 'package:gps_cielo/core/services/address_suggestion_service.dart';
import 'package:gps_cielo/core/data/user_repository.dart';
import 'package:gps_cielo/core/services/home_address_service.dart';
import 'package:gps_cielo/core/services/household_store.dart';
import 'package:gps_cielo/features/neighborhood/domain/services/neighborhood_service.dart';
import 'package:gps_cielo/features/neighborhood/presentation/controllers/neighborhood_controller.dart';
import 'package:gps_cielo/core/services/location_service.dart';
import 'package:gps_cielo/features/home/domain/services/home_service.dart';

import 'support/fake_household_repository.dart';

class FakeUserRepository implements UserRepository {
  final locations =
      <({String uid, String address, double latitude, double longitude})>[];

  @override
  Future<void> updateLocation({
    required String uid,
    required String address,
    required double latitude,
    required double longitude,
    int? radiusHomes,
  }) async {
    locations.add((
      uid: uid,
      address: address,
      latitude: latitude,
      longitude: longitude,
    ));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _SylhetPhoton implements AddressSearchProvider {
  @override
  String get attribution => '';

  @override
  Future<AddressSuggestion?> reverse(double latitude, double longitude) async =>
      null;

  @override
  Future<List<AddressSuggestion>> search(
    String query, {
    double? nearLatitude,
    double? nearLongitude,
    int limit = 5,
  }) async => const [
    AddressSuggestion(
      title: 'Zindabazar',
      subtitle: 'Sylhet',
      latitude: 24.896,
      longitude: 91.868,
    ),
  ];
}

UserModel user({
  String id = 'alice',
  double? latitude = 23.7465,
  double? longitude = 90.376,
  String address = 'Dhanmondi, Dhaka',
  int radiusHomes = 10,
  double rangeKm = 5,
}) => UserModel(
  id: id,
  fullName: 'Test',
  email: '$id@example.com',
  address: address,
  latitude: latitude,
  longitude: longitude,
  radiusHomes: radiusHomes,
  searchRadiusKm: rangeKm,
);

const uttara = ResolvedLocation(
  address: 'Uttara, Dhaka',
  latitude: 23.8759,
  longitude: 90.3795,
  source: LocationSource.search,
);

void main() {
  late FakeHouseholdRepository repository;
  late HouseholdStore store;

  setUp(() {
    Get.testMode = true;
    repository = FakeHouseholdRepository();
    store = HouseholdStore(repository, FakeNotificationRepository());
  });

  test('loads households around the saved home location', () async {
    await store.bindUser(user());
    expect(repository.fetches.single.latitude, 23.7465);
    expect(repository.fetches.single.radiusKm, 5);
    expect(store.center.value?.isTemporary, isFalse);
    expect(store.center.value?.label, 'Dhanmondi, Dhaka');
  });

  test('no location means no query', () async {
    await store.bindUser(user(latitude: null, longitude: null));
    expect(repository.fetches, isEmpty);
    expect(store.center.value, isNull);
  });

  test(
    'a temporary search moves the center without touching the profile',
    () async {
      await store.bindUser(user());
      await store.searchAround(uttara);

      expect(repository.fetches.last.latitude, 23.8759);
      expect(store.isTemporarySearch, isTrue);
      expect(store.center.value?.label, 'Uttara, Dhaka');
      expect(store.center.value?.isTemporary, isTrue);
    },
  );

  test(
    'profile updates keep the temporary search; a new range reloads it',
    () async {
      await store.bindUser(user());
      await store.searchAround(uttara);
      final before = repository.fetches.length;

      await store.bindUser(user()); // e.g. name changed
      expect(repository.fetches.length, before);
      expect(store.isTemporarySearch, isTrue);

      final reloadFrom = repository.fetches.length;
      await store.bindUser(user(rangeKm: 10));
      final reloads = repository.fetches.skip(reloadFrom).toList();
      // The search on screen (Uttara) and the home neighborhood both reload.
      expect(
        reloads.map((f) => (f.latitude, f.radiusKm)),
        containsAll([(23.8759, 10.0), (23.7465, 10.0)]),
      );
      expect(store.isTemporarySearch, isTrue);
    },
  );

  test('useSavedLocation returns to home', () async {
    await store.bindUser(user());
    await store.searchAround(uttara);
    await store.useSavedLocation();
    expect(store.isTemporarySearch, isFalse);
    expect(repository.fetches.last.latitude, 23.7465);
  });

  test('saving a new home address discards the temporary search', () async {
    await store.bindUser(user());
    await store.searchAround(uttara);
    store.discardTemporarySearch();
    await store.bindUser(user(latitude: 22.3260, longitude: 91.8120));
    expect(store.isTemporarySearch, isFalse);
    expect(repository.fetches.last.latitude, 22.3260);
  });

  test('switching accounts clears the previous temporary search', () async {
    await store.bindUser(user());
    await store.searchAround(uttara);
    await store.bindUser(user(id: 'bob'));
    expect(store.isTemporarySearch, isFalse);
    expect(repository.fetches.last.latitude, 23.7465);
  });

  test('searchAround is ignored when signed out', () async {
    await store.searchAround(uttara);
    expect(repository.fetches, isEmpty);
  });

  test('status writes go to the signed-in user only', () async {
    await store.bindUser(user());
    store.households.add(
      HouseholdModel(
        id: 'demo_bd_001',
        number: 1,
        residentName: 'Demo Household 001',
        address: 'Demo',
      ),
    );
    await store.togglePray('demo_bd_001');
    expect(repository.savedStatuses.single.uid, 'alice');
  });

  // HomeService has no UserRepository at all, so nothing on Home (search,
  // GPS or the range filter) can write the profile.
  HomeService homeService() => HomeService(
    store,
    LocationService(
      addressSearch: AddressSuggestionService(
        provider: _SylhetPhoton(),
        minInterval: Duration.zero,
      ),
    ),
    FakeNotificationRepository(),
  );

  test('HomeService.searchNeighborhood is temporary', () async {
    final service = homeService();
    await store.bindUser(user());
    final location = await service.searchNeighborhood('Zindabazar, Sylhet');

    expect(location.latitude, 24.896);
    expect(store.center.value?.isTemporary, isTrue);
    expect(repository.fetches.last.latitude, 24.896);

    await service.useSavedLocation();
    expect(store.center.value?.isTemporary, isFalse);
  });

  group('search range (km) and number of households', () {
    test(
      'searches within the Settings range and shows the default count',
      () async {
        repository.available = 40;
        await store.bindUser(user(radiusHomes: 15, rangeKm: 5));
        expect(repository.fetches.last.radiusKm, 5);
        expect(store.rangeMeters.value, 5000);
        // The nearest are read first (25 = the largest Home count); the
        // rest of the range only when asked for.
        expect(store.foundInRange.value, greaterThanOrEqualTo(25));
        expect(store.areaComplete.value, store.foundInRange.value == 40);
        expect(store.households.length, 15);
        expect(store.households.first.id, 'demo_0');
        await store.loadMoreArea(1000);
        expect(store.areaComplete.value, isTrue);
        expect(store.areaHouseholds.length, 40);
        expect(store.foundInRange.value, 40);
        expect(repository.lastIndex!.documentsRead, 40);
        expect(store.activeRadius.value, 15);
        expect(store.defaultHomes.value, 15);
        expect(store.isRadiusFiltered.value, isFalse);
      },
    );

    test('a small range shows only what is inside it', () async {
      repository.available = 40;
      await store.bindUser(user(radiusHomes: 10, rangeKm: 0.5));
      // Homes are 100 m apart: only 5 are within 500 m.
      expect(store.foundInRange.value, 5);
      expect(store.households.length, 5);
    });

    test(
      'the Home count changes the list, never the range or the query',
      () async {
        repository.available = 40;
        final service = homeService();
        await store.bindUser(user(radiusHomes: 10, rangeKm: 5));
        final fetches = repository.fetches.length;

        await service.filterRadius(20);
        expect(store.households.length, 20);
        expect(store.households.first.id, 'demo_0');
        expect(store.isRadiusFiltered.value, isTrue);

        await service.filterRadius(5);
        expect(store.households.length, 5);
        expect(store.households.last.id, 'demo_4');

        expect(store.rangeMeters.value, 5000);
        expect(repository.fetches.length, fetches);
      },
    );

    test('the count filter survives a temporary search', () async {
      repository.available = 40;
      final service = homeService();
      await store.bindUser(user(radiusHomes: 10));
      await service.filterRadius(5);
      await store.searchAround(uttara);
      expect(repository.fetches.last.latitude, uttara.latitude);
      expect(repository.fetches.last.radiusKm, 5);
      expect(store.households.length, 5);
    });

    test('Default (or picking the default) clears the filter', () async {
      repository.available = 40;
      final service = homeService();
      await store.bindUser(user(radiusHomes: 10));
      await service.filterRadius(25);
      await service.filterRadius(null);
      expect(store.households.length, 10);
      expect(store.isRadiusFiltered.value, isFalse);

      await service.filterRadius(5);
      await service.filterRadius(10);
      expect(store.isRadiusFiltered.value, isFalse);
    });

    test(
      'a new range from Settings reloads and keeps the Home count',
      () async {
        repository.available = 40;
        final service = homeService();
        await store.bindUser(user(radiusHomes: 10, rangeKm: 5));
        await service.filterRadius(20);

        await store.bindUser(user(radiusHomes: 10, rangeKm: 1));

        expect(repository.fetches.last.radiusKm, 1);
        expect(store.rangeMeters.value, 1000);
        expect(store.households.length, 10); // only 10 within 1 km
        expect(store.activeRadius.value, 20);
      },
    );

    test(
      'a new default count from Settings replaces the Home filter',
      () async {
        repository.available = 40;
        final service = homeService();
        await store.bindUser(user(radiusHomes: 10));
        await service.filterRadius(25);
        final fetches = repository.fetches.length;

        await store.bindUser(user(radiusHomes: 15));

        expect(store.households.length, 15);
        expect(store.isRadiusFiltered.value, isFalse);
        expect(repository.fetches.length, fetches); // no new query needed
      },
    );

    test('signing in as someone else clears the filter', () async {
      repository.available = 40;
      final service = homeService();
      await store.bindUser(user(radiusHomes: 10));
      await service.filterRadius(5);
      await store.bindUser(user(id: 'bob', radiusHomes: 10));
      expect(store.households.length, 10);
      expect(store.isRadiusFiltered.value, isFalse);
    });
  });

  group('prayer list neighborhood and status changes', () {
    Future<void> flush() => Future<void>.delayed(Duration.zero);

    test(
      'my neighborhood stays at home during a search and a Home filter',
      () async {
        repository.available = 40;
        final service = homeService();
        await store.bindUser(user(radiusHomes: 10));
        final home = store.homeHouseholds.map((h) => h.id).toList();
        expect(home.length, 10);

        await store.searchAround(uttara);
        await service.filterRadius(5);
        expect(store.households.length, 5);
        expect(store.homeHouseholds.map((h) => h.id), home);
        expect(store.homeHouseholds.first.latitude, closeTo(23.7474, 0.0001));
      },
    );

    test('the Settings count sets the size of my neighborhood', () async {
      repository.available = 40;
      await store.bindUser(user(radiusHomes: 10));
      await store.bindUser(user(radiusHomes: 20));
      expect(store.homeHouseholds.length, 20);
    });

    test('praying updates every list at once', () async {
      repository.available = 5;
      await store.bindUser(user());
      await store.togglePray('demo_0');
      expect(store.homeHouseholds.first.isPrayed, isTrue);
      expect(store.households.first.isPrayed, isTrue);
      expect(store.trackedHouseholds.single.id, 'demo_0');
      expect(store.prayedCount.value, 1);

      await store.togglePray('demo_0');
      expect(store.homeHouseholds.first.isPrayed, isFalse);
      expect(store.trackedHouseholds, isEmpty);
      expect(store.prayedCount.value, 0);
    });

    test(
      'a household outside the search area is still tracked and editable',
      () async {
        repository.available = 3;
        await store.bindUser(user());
        repository.emitStatuses('alice', {
          'far_away': {
            'isPrayed': false,
            'hasFollowUp': true,
            'followUpDate': '10/01/2026',
            'residentName': 'Far Away',
            'address': 'Sylhet',
            'updatedAt': Timestamp.now(),
          },
        });
        await flush();
        expect(store.trackedHouseholds.single.residentName, 'Far Away');

        await store.toggleVisited('far_away');
        expect(repository.savedStatuses.last.householdId, 'far_away');
        expect(store.findById('far_away')?.isVisited, isTrue);
      },
    );

    test(
      'a new cycle makes everyone pray-able again; lifetime counts stay',
      () async {
        repository.available = 2;
        await store.bindUser(user());
        final lastWeek = Timestamp.fromDate(
          DateTime.now().subtract(const Duration(days: 7)),
        );
        repository.emitStatuses('alice', {
          'demo_0': {'isPrayed': true, 'prayedAt': lastWeek},
          'demo_1': {'isPrayed': true, 'prayedAt': lastWeek},
        });
        await flush();
        expect(store.homeHouseholds.every((h) => h.isPrayed), isTrue);

        await store.bindUser(
          user().copyWith(prayerCycleStartedAt: DateTime.now()),
        );
        expect(store.homeHouseholds.any((h) => h.isPrayed), isFalse);
        expect(store.prayedCount.value, 2);

        // Praying again in the new cycle counts.
        await store.togglePray('demo_0');
        expect(store.homeHouseholds.first.isPrayed, isTrue);
      },
    );

    test('a failed save restores the previous status', () async {
      repository.available = 2;
      await store.bindUser(user());
      repository.failWith = Exception('offline');
      try {
        await store.togglePray('demo_0');
      } catch (_) {
        // The error snackbar needs an app; the status must still be restored.
      }
      expect(store.homeHouseholds.first.isPrayed, isFalse);
      expect(store.trackedHouseholds, isEmpty);
    });
  });

  group('set a searched place as home', () {
    test(
      'saves the place, ends the search and moves my neighborhood',
      () async {
        repository.available = 12;
        final users = FakeUserRepository();
        final homeAddress = HomeAddressService(users, store);
        final alice = user(radiusHomes: 10);
        await store.bindUser(alice);
        await store.searchAround(uttara);
        expect(store.homeHouseholds.first.latitude, closeTo(23.7474, 0.0001));
        final fetches = repository.fetches.length;

        await homeAddress.save(alice, uttara);

        expect(users.locations.single.address, 'Uttara, Dhaka');
        expect(users.locations.single.latitude, 23.8759);
        expect(store.isTemporarySearch, isFalse);
        expect(store.center.value?.isTemporary, isFalse);
        // The Uttara results already on screen become "my neighborhood".
        expect(repository.fetches.length, fetches);
        expect(store.homeHouseholds.first.latitude, closeTo(23.8768, 0.0001));
        expect(store.isNearHome('demo_0'), isTrue);
      },
    );

    test('a household found elsewhere is not near home', () async {
      repository.available = 3;
      await store.bindUser(user());
      expect(store.isNearHome('demo_0'), isTrue);
      expect(store.isNearHome('far_away'), isFalse);
    });
  });

  group('Neighborhood paging', () {
    tearDown(Get.reset);

    test('lists every household in range, 10 at a time', () async {
      repository.available = 40;
      await store.bindUser(user(radiusHomes: 20, rangeKm: 5));
      final controller = Get.put(
        NeighborhoodController(NeighborhoodService(store)),
      );

      expect(controller.households.length, 20); // map pins (Settings count)
      // Only the nearest are read up front; the rest as the list scrolls.
      expect(controller.areaHouseholds.length, lessThan(40));
      expect(controller.areaComplete.value, isFalse);
      expect(controller.pagedHouseholds.length, 10);
      expect(controller.hasMore, isTrue);

      // Scroll to the end until nothing more comes, letting reads finish.
      for (var i = 0; i < 20 && controller.hasMore; i++) {
        controller.loadMore();
        await pumpEventQueue();
      }
      expect(controller.areaComplete.value, isTrue);
      expect(controller.pagedHouseholds.length, 40);
      expect(controller.hasMore, isFalse);
      expect(controller.loadMore(), isFalse);
      final ids = controller.pagedHouseholds.map((h) => h.id).toList();
      // Every household, once, nearest first.
      expect(ids, [for (var i = 0; i < 40; i++) 'demo_$i']);
      // No household document was read twice.
      expect(repository.lastIndex!.documentsRead, 40);
    });

    test(
      'a page asked for before it is read appears when it arrives',
      () async {
        repository.available = 40;
        await store.bindUser(user(radiusHomes: 10, rangeKm: 5));
        final controller = Get.put(
          NeighborhoodController(NeighborhoodService(store)),
        );
        // Show everything already read, then ask for one more page.
        while (controller.visibleCount.value <
            controller.areaHouseholds.length) {
          controller.visibleCount.value += NeighborhoodController.pageSize;
        }
        final before = controller.visibleCount.value;
        expect(controller.loadMore(), isFalse); // not read yet
        await pumpEventQueue();
        expect(controller.visibleCount.value, before + 10);
        expect(controller.pagedHouseholds.length, greaterThan(before));
      },
    );

    test(
      'reaching the end when nothing more is in range stops the spinner',
      () async {
        // 26 households (the last 2.6 km out); the first read takes the
        // nearest 25+, so the last read only confirms the range is empty.
        repository.available = 26;
        await store.bindUser(user(radiusHomes: 10, rangeKm: 5));
        final controller = Get.put(
          NeighborhoodController(NeighborhoodService(store)),
        );
        for (var i = 0; i < 10 && controller.hasMore; i++) {
          controller.loadMore();
          await pumpEventQueue();
        }
        expect(controller.areaComplete.value, isTrue);
        expect(controller.isLoadingMore.value, isFalse); // no stuck spinner
        expect(controller.hasMore, isFalse); // footer: "All 26 shown"
        expect(controller.pagedHouseholds.length, 26);
      },
    );

    test('a new search area starts again at page one', () async {
      repository.available = 40;
      await store.bindUser(user());
      final controller = Get.put(
        NeighborhoodController(NeighborhoodService(store)),
      );
      controller.loadMore();
      expect(controller.pagedHouseholds.length, 20);

      await store.searchAround(uttara);
      expect(controller.pagedHouseholds.length, 10);
    });
  });

  group('bounded status reads', () {
    test(
      'reads statuses only for loaded households; totals from counts',
      () async {
        repository.available = 40;
        // 500 statuses on the server, most for households far away.
        repository.serverStatuses['alice'] = {
          for (var i = 0; i < 500; i++)
            'h_$i': {'isPrayed': i.isEven, 'isVisited': i % 5 == 0},
          'demo_0': {'isPrayed': true},
        };
        await store.bindUser(user(radiusHomes: 10, rangeKm: 5));
        await pumpEventQueue();

        final loaded = store.areaHouseholds.map((h) => h.id).toSet();
        expect(repository.statusReads.toSet(), loaded);
        expect(repository.statusReads.length, loaded.length); // once each
        expect(
          repository.statusReads.any((id) => id.startsWith('h_')),
          isFalse,
        );
        expect(store.households.first.isPrayed, isTrue);

        // Lifetime totals cover all 501 without downloading them.
        expect(store.statusCounts['all'], 501);
        expect(store.prayedCount.value, 251);
        expect(store.visitedCount.value, 100);
      },
    );
  });
}
