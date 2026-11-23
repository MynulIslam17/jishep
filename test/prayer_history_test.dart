import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gps_cielo/core/constants/firestore_paths.dart';
import 'package:gps_cielo/core/data/household_repository.dart';
import 'package:gps_cielo/core/data/user_repository.dart';
import 'package:gps_cielo/core/data/geo_record.dart';
import 'package:gps_cielo/core/models/household_model.dart';
import 'package:gps_cielo/core/models/prayer_round.dart';

// Prayer history: append-only events per round, rounds with the same homes.
void main() {
  late FakeFirebaseFirestore db;
  late HouseholdRepository households;
  late UserRepository users;
  const uid = 'me';

  HouseholdModel home(String id, {bool prayed = false}) =>
      HouseholdModel(id: id, number: 1, address: '1 TEST ST', isPrayed: prayed);

  Future<void> pray(String id, String round) => households.saveStatus(
    uid: uid,
    household: home(id, prayed: true),
    wasPrayed: false,
    roundId: round,
  );

  PrayerRound roundOf(List<String> ids) => PrayerRound(
    members: [
      for (final id in ids)
        GeoRecord(
          id: id,
          latitude: 32.6,
          longitude: -117.0,
          geohash: '',
          address: '1 TEST ST',
        ),
    ],
  );

  setUp(() {
    db = FakeFirebaseFirestore();
    households = HouseholdRepository(firestore: db);
    users = UserRepository(firestore: db);
  });

  test(
    'praying writes the status AND one history event for the round',
    () async {
      await pray('mel:1', 'r0');
      final status = await db.doc('users/me/household_status/mel:1').get();
      expect(status.get('isPrayed'), isTrue);
      final event = await db.doc('users/me/prayer_log/r0_mel:1').get();
      expect(event.get('householdId'), 'mel:1');
      expect(event.get('roundId'), 'r0');
      expect(event.get('prayedAt'), isA<Timestamp>());
    },
  );

  test(
    'a new round never overwrites earlier prayers (lifetime history)',
    () async {
      await pray('mel:1', 'r0');
      await pray('mel:2', 'r0');
      final round2 = FirestorePaths.roundId(DateTime(2026, 12, 1));
      await pray('mel:1', round2); // the same home, prayed again next round
      expect(await households.countPrayerEvents(uid), 3);
      expect(
        (await households.fetchPrayerEvents(uid, roundId: 'r0')).length,
        2,
      );
      expect(
        (await households.fetchPrayerEvents(uid, roundId: round2)).length,
        1,
      );
      // The status holds only the latest prayer; history keeps both.
      final events = await households.fetchPrayerEvents(uid);
      expect(events.where((e) => e['householdId'] == 'mel:1').length, 2);
    },
  );

  test('praying twice in one round is one event (idempotent id)', () async {
    await pray('mel:1', 'r0');
    await pray('mel:1', 'r0');
    expect(await households.countPrayerEvents(uid), 1);
  });

  test('un-praying corrects only the current round', () async {
    await pray('mel:1', 'r0');
    await pray('mel:1', 'r5');
    await households.saveStatus(
      uid: uid,
      household: home('mel:1'),
      wasPrayed: true,
      roundId: 'r5',
    );
    expect(
      (await db.doc('users/me/prayer_log/r5_mel:1').get()).exists,
      isFalse,
    );
    expect((await db.doc('users/me/prayer_log/r0_mel:1').get()).exists, isTrue);
  });

  test(
    'a new round keeps the same homes, closes the old round, keeps history',
    () async {
      await db.doc('users/me').set({'fullName': 'Me'});
      await pray('mel:1', 'r0');
      await db.doc('users/me/household_status/mel:2').set({
        'isPrayed': false,
        'isVisited': true,
        'isInvited': true,
        'hasFollowUp': true,
        'followUpDate': '12/01/2026',
      });
      final ids = [for (var i = 1; i <= 50; i++) 'mel:$i'];
      await users.startPrayerRound(
        uid,
        previousStart: null,
        round: roundOf(ids),
      );
      await Future<void>.delayed(Duration.zero);

      final user = await db.doc('users/me').get();
      final start = (user.get('prayerCycleStartedAt') as Timestamp).toDate();
      final round = await db
          .doc('users/me/prayer_rounds/${FirestorePaths.roundId(start)}')
          .get();
      expect(round.get('householdIds'), ids);
      expect(round.get('size'), 50);
      expect(
        (await db.doc('users/me/prayer_rounds/r0').get()).get('completedAt'),
        isA<Timestamp>(),
      );
      // History, visits, invitations and follow-ups untouched.
      expect(await households.countPrayerEvents(uid), 1);
      final other = await db.doc('users/me/household_status/mel:2').get();
      expect(other.get('isVisited'), isTrue);
      expect(other.get('hasFollowUp'), isTrue);
    },
  );

  test('users are independent', () async {
    await pray('mel:1', 'r0');
    await households.saveStatus(
      uid: 'other',
      household: home('mel:1', prayed: true),
      wasPrayed: false,
      roundId: 'r0',
    );
    expect(await households.countPrayerEvents('me'), 1);
    expect(await households.countPrayerEvents('other'), 1);
  });

  test('account deletion removes prayer history and rounds', () async {
    await db.doc('users/me').set({'fullName': 'Me'});
    await pray('mel:1', 'r0');
    await users.startPrayerRound(
      uid,
      previousStart: null,
      round: roundOf(['mel:1']),
    );
    await Future<void>.delayed(Duration.zero);
    await users.deleteUserData(uid);
    expect((await db.collection('users/me/prayer_log').get()).size, 0);
    expect((await db.collection('users/me/prayer_rounds').get()).size, 0);
  });

  test('round ids: r0 first, then the start time', () {
    expect(FirestorePaths.roundId(null), 'r0');
    final t = DateTime.fromMillisecondsSinceEpoch(1764000000000);
    expect(FirestorePaths.roundId(t), 'r1764000000000');
    expect(FirestorePaths.prayerEventId('r0', 'mel:1'), 'r0_mel:1');
  });
}
