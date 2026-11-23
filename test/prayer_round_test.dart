import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:gps_cielo/core/config/feature_flags.dart';
import 'package:gps_cielo/core/constants/firestore_paths.dart';
import 'package:gps_cielo/core/data/geo_record.dart';
import 'package:gps_cielo/core/data/user_repository.dart';
import 'package:gps_cielo/core/models/prayer_round.dart';
import 'package:gps_cielo/core/models/user_model.dart';
import 'package:gps_cielo/core/services/household_store.dart';
import 'package:gps_cielo/core/services/location_service.dart';
import 'package:gps_cielo/core/utils/day_change.dart';
import 'package:gps_cielo/features/prayer_list/domain/services/prayer_list_service.dart';

import 'support/fake_household_repository.dart';

/// Records rounds started (what the Prayer List writes).
class _RoundUsers implements UserRepository {
  final started = <({String uid, PrayerRound round, DateTime? at})>[];

  @override
  Future<void> startPrayerRound(
    String uid, {
    required DateTime? previousStart,
    required PrayerRound round,
    DateTime? at,
  }) async {
    started.add((uid: uid, round: round, at: at));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

UserModel _user({
  String id = 'alice',
  double latitude = 32.6453,
  double longitude = -117.0081,
  int radiusHomes = 10,
  DateTime? roundStart,
}) => UserModel(
  id: id,
  fullName: 'Test',
  email: '$id@example.test',
  address: '1 Test St',
  latitude: latitude,
  longitude: longitude,
  radiusHomes: radiusHomes,
  searchRadiusKm: 5,
  prayerCycleStartedAt: roundStart,
);

void main() {
  setUp(() {
    Get.testMode = true;
    FeatureFlags.useCellHouseholds = false;
  });
  tearDown(
    () => FeatureFlags.useCellHouseholds = FeatureFlags.cellHouseholdsDefault,
  );

  late FakeHouseholdRepository repository;
  late HouseholdStore store;
  Future<void> settle() => Future<void>.delayed(Duration.zero);
  List<String> homeIds([HouseholdStore? s]) => [
    for (final h in (s ?? store).homeHouseholds) h.id,
  ];

  setUp(() {
    repository = FakeHouseholdRepository()..available = 60;
    store = HouseholdStore(repository, FakeNotificationRepository());
  });

  group('round membership is fixed', () {
    test('the first load records the round\'s homes and center', () async {
      await store.bindUser(_user());
      await settle();
      expect(homeIds(), [for (var i = 0; i < 10; i++) 'demo_$i']);
      final write = repository.roundWrites.single;
      expect(write.roundId, 'r0');
      expect(write.ids, homeIds());
      final round = repository.rounds['alice']!['r0']!;
      expect(round.centerLatitude, 32.6453);
      expect(round.target, 10);
    });

    test('a changed cache answer never changes an active round', () async {
      await store.bindUser(_user());
      await settle();
      final fixed = homeIds();

      repository.idPrefix = 'other_'; // the cache now answers differently
      await store.refreshHome();
      await store.refreshHouseholds();
      await settle();
      expect(homeIds(), fixed);
      expect(repository.roundWrites, hasLength(1));
    });

    test(
      'a round read back after a restart shows its recorded homes',
      () async {
        final members = [
          for (var i = 0; i < 3; i++)
            GeoRecord(
              id: 'mel:$i',
              latitude: 32.645 + i / 10000,
              longitude: -117.008,
              geohash: '',
              address: '$i RECORDED ST',
            ),
        ];
        repository.rounds['alice'] = {
          'r0': PrayerRound(
            members: members,
            centerLatitude: 32.6453,
            centerLongitude: -117.0081,
            target: 10,
          ),
        };
        await store.bindUser(_user());
        await settle();
        expect(homeIds(), ['mel:0', 'mel:1', 'mel:2']);
        expect(store.homeHouseholds.first.address, '0 RECORDED ST');
        expect(repository.roundWrites, isEmpty);
      },
    );

    test('searching elsewhere never changes the round', () async {
      await store.bindUser(_user());
      await settle();
      final fixed = homeIds();
      await store.searchAround(
        const ResolvedLocation(
          address: 'Elsewhere',
          latitude: 32.75,
          longitude: -117.1,
          source: LocationSource.search,
        ),
      );
      await settle();
      expect(homeIds(), fixed);
      expect(repository.roundWrites, hasLength(1));
    });

    test(
      'moving the saved home gives the round the new neighborhood',
      () async {
        await store.bindUser(_user());
        await settle();
        repository.idPrefix = 'moved_';
        await store.bindUser(_user(latitude: 32.70)); // ~6 km away
        await settle();
        expect(homeIds(), [for (var i = 0; i < 10; i++) 'moved_$i']);
        expect(repository.roundWrites.last.roundId, 'r0');
      },
    );

    test('a few meters of pin adjustment keeps the round', () async {
      await store.bindUser(_user());
      await settle();
      final fixed = homeIds();
      repository.idPrefix = 'other_';
      await store.bindUser(_user(latitude: 32.6453 + 0.0002)); // ~22 m
      await settle();
      expect(homeIds(), fixed);
    });

    test('a new Settings count keeps the homes and adds the nearest', () async {
      await store.bindUser(_user(radiusHomes: 5));
      await settle();
      repository.idPrefix = 'other_';
      await store.refreshHome(); // the cache answers differently now
      await settle();
      expect(homeIds(), [for (var i = 0; i < 5; i++) 'demo_$i']);
      await store.bindUser(_user(radiusHomes: 7));
      await settle();
      expect(homeIds(), [
        for (var i = 0; i < 5; i++) 'demo_$i',
        'other_0',
        'other_1',
      ]);
    });

    test(
      'rules without prayer_rounds: nearest homes, nothing written',
      () async {
        repository.roundReadError = Exception('permission-denied');
        await store.bindUser(_user());
        await settle();
        expect(homeIds(), [for (var i = 0; i < 10; i++) 'demo_$i']);
        expect(repository.roundWrites, isEmpty);
      },
    );
  });

  group('every new round reuses the same homes', () {
    test('three rounds in a row, even after the cache changed', () async {
      final users = _RoundUsers();
      final service = PrayerListService(store, users);
      await store.bindUser(_user());
      await settle();
      final fixed = homeIds();

      var start = DateTime(2026, 11, 1);
      for (var round = 2; round <= 4; round++) {
        repository.idPrefix = 'changed$round';
        await service.startNewCycle('alice');
        final started = users.started.last;
        expect(started.round.ids, fixed);
        start = started.at!;
        // The profile change comes back from Firestore.
        await store.bindUser(_user(roundStart: start));
        await settle();
        expect(homeIds(), fixed, reason: 'round $round');
        expect(store.homeHouseholds.any((h) => h.isPrayed), isFalse);
      }
      // Rounds are never re-fixed from the cache.
      expect(repository.roundWrites, hasLength(1));
    });

    test('prayers go to the current round id', () async {
      final users = _RoundUsers();
      final service = PrayerListService(store, users);
      await store.bindUser(_user());
      await settle();
      await store.togglePray('demo_0');
      await service.startNewCycle('alice');
      final at = users.started.last.at!;
      await store.bindUser(_user(roundStart: at));
      await settle();
      await store.togglePray('demo_0');
      expect(repository.savedRounds, ['r0', FirestorePaths.roundId(at)]);
    });
  });

  group('lifetime prayers', () {
    test('from the history, kept current by local prayers', () async {
      repository.prayerEvents['alice'] = 7;
      repository.serverStatuses['alice'] = {
        'demo_0': {'isPrayed': true},
      };
      await store.bindUser(_user());
      await settle();
      expect(store.prayersOffered.value, 7);
      await store.togglePray('demo_1');
      expect(store.prayersOffered.value, 8);
      await store.togglePray('demo_1');
      expect(store.prayersOffered.value, 7);
    });

    test('never below homes prayed (prayers before the history)', () async {
      repository.serverStatuses['alice'] = {
        'demo_0': {'isPrayed': true},
        'demo_1': {'isPrayed': true},
        'demo_2': {'isPrayed': true},
      };
      await store.bindUser(_user());
      await settle();
      expect(store.prayedCount.value, 3);
      expect(store.prayersOffered.value, 3);
    });

    test('a failed save takes the prayer back', () async {
      await store.bindUser(_user());
      await settle();
      repository.failWith = Exception('offline');
      try {
        await store.togglePray('demo_0');
      } catch (_) {}
      expect(store.prayersOffered.value, 0);
    });
  });

  group('users are independent', () {
    test(
      'two users at the same place: own rounds, prayers, follow-ups',
      () async {
        final bob = HouseholdStore(repository, FakeNotificationRepository());
        repository.prayerEvents['alice'] = 4;
        await store.bindUser(_user());
        await bob.bindUser(_user(id: 'bob', radiusHomes: 5));
        await settle();

        await store.togglePray('demo_0');
        await store.toggleFollowUp('demo_1');
        expect(store.homeHouseholds.first.isPrayed, isTrue);
        expect(bob.homeHouseholds.first.isPrayed, isFalse);
        expect(bob.trackedHouseholds, isEmpty);
        expect(store.prayersOffered.value, 5);
        expect(bob.prayersOffered.value, 0);
        expect(homeIds(bob), hasLength(5));
        expect(repository.rounds.keys, containsAll(['alice', 'bob']));
        expect(repository.rounds['bob']!['r0']!.ids, hasLength(5));
        expect(repository.savedStatuses.map((s) => s.uid).toSet(), {'alice'});
      },
    );

    test(
      'signing in as someone else forgets the first user\'s round',
      () async {
        await store.bindUser(_user());
        await settle();
        repository.idPrefix = 'bob_';
        await store.bindUser(_user(id: 'bob'));
        await settle();
        expect(homeIds().first, 'bob_0');
        expect(store.prayersOffered.value, 0);
      },
    );
  });

  group('history documents (Firestore)', () {
    test(
      'a new round document holds the same members, no owner names',
      () async {
        final db = FakeFirebaseFirestore();
        final users = UserRepository(firestore: db);
        await db.doc('users/me').set({'fullName': 'Me'});
        final round = PrayerRound(
          members: [
            for (var i = 0; i < 50; i++)
              GeoRecord(
                id: 'mel:$i',
                latitude: 32.6,
                longitude: -117.0,
                geohash: '',
                address: '$i ST',
                ownerName: 'SECRET OWNER',
              ),
          ],
          centerLatitude: 32.6,
          centerLongitude: -117.0,
          target: 50,
        );
        final at = DateTime(2026, 11, 22, 9);
        await users.startPrayerRound(
          'me',
          previousStart: null,
          round: round,
          at: at,
        );
        await settle();
        final doc = await db
            .doc('users/me/prayer_rounds/${FirestorePaths.roundId(at)}')
            .get();
        expect(doc.get('size'), 50);
        expect(PrayerRound.fromFirestore(doc.data())!.ids, round.ids);
        expect(doc.data().toString(), isNot(contains('SECRET')));
        expect(doc.get('center'), isA<GeoPoint>());
        final user = await db.doc('users/me').get();
        expect((user.get('prayerCycleStartedAt') as Timestamp).toDate(), at);
      },
    );
  });

  group('day change', () {
    test('fires once when the date changes (midnight or resume)', () {
      var now = DateTime(2026, 11, 22, 23, 59);
      var calls = 0;
      final watcher = DayChangeWatcher(() => calls++, clock: () => now);
      watcher.check();
      expect(calls, 0);
      now = DateTime(2026, 11, 23, 0, 0, 1);
      watcher.check();
      watcher.check();
      expect(calls, 1);
      now = DateTime(2026, 11, 25, 8);
      watcher.check();
      expect(calls, 2);
      watcher.dispose();
    });
  });
}
