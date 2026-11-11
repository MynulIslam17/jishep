import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gps_cielo/core/models/household_model.dart';
import 'package:gps_cielo/core/models/user_model.dart';
import 'package:gps_cielo/core/utils/firebase_error_mapper.dart';
import 'package:gps_cielo/core/utils/follow_up_date.dart';
import 'package:gps_cielo/features/prayer_list/domain/services/prayer_list_service.dart';

HouseholdModel household(
  int number, {
  bool isPrayed = false,
  DateTime? prayedAt,
}) {
  return HouseholdModel(
    id: 'h$number',
    number: number,
    residentName: 'Resident $number',
    address: '$number Main St',
    isPrayed: isPrayed,
    prayedAt: prayedAt,
  );
}

void main() {
  group('PrayerListService.buildPlan', () {
    final now = DateTime(2026, 9, 17, 15);
    List<int> numbers(PrayerPlan plan) =>
        plan.today.map((h) => h.number).toList();

    test('fills the daily target with unprayed households, nearest first', () {
      final plan = PrayerListService.buildPlan(
        [household(1), household(2), household(3), household(4)],
        3,
        now: now,
      );
      expect(numbers(plan), [1, 2, 3]);
      expect(plan.prayedToday, 0);
      expect(plan.cycleTotal, 4);
      expect(plan.cycleRemaining, 4);
      expect(plan.daysLeft, 2);
    });

    test('keeps households prayed today and skips ones prayed earlier', () {
      final plan = PrayerListService.buildPlan(
        [
          household(1, isPrayed: true, prayedAt: DateTime(2026, 9, 10)),
          household(2, isPrayed: true, prayedAt: DateTime(2026, 9, 17, 9)),
          household(3),
          household(4),
        ],
        2,
        now: now,
      );
      expect(numbers(plan), [2, 3]);
      expect(plan.prayedToday, 1);
      expect(plan.cyclePrayed, 2);
    });

    test('praying for a household does not change the list size', () {
      final before = PrayerListService.buildPlan(
        [household(1), household(2), household(3)],
        2,
        now: now,
      );
      final after = PrayerListService.buildPlan(
        [
          household(1, isPrayed: true, prayedAt: now),
          household(2),
          household(3),
        ],
        2,
        now: now,
      );
      expect(numbers(before), [1, 2]);
      expect(numbers(after), [1, 2]);
      expect(after.isTodayDone, isFalse);
    });

    test('changing the goal mid-day keeps today\'s prayers and refits', () {
      // Goal 10/day, 5 already prayed today, 20 neighbors.
      final homes = [
        for (var i = 1; i <= 5; i++)
          household(i, isPrayed: true, prayedAt: DateTime(2026, 9, 17, 9)),
        for (var i = 6; i <= 20; i++) household(i),
      ];

      final ten = PrayerListService.buildPlan(homes, 10, now: now);
      expect(ten.today.length, 10);
      expect(ten.prayedToday, 5);
      expect(ten.isTodayDone, isFalse);

      // Raised to 15: the 5 prayed stay, 10 more are added.
      final fifteen = PrayerListService.buildPlan(homes, 15, now: now);
      expect(fifteen.today.length, 15);
      expect(numbers(fifteen).take(5), [1, 2, 3, 4, 5]);
      expect(fifteen.isTodayDone, isFalse);

      // Lowered to 3: today's 5 prayers still count and today is done.
      final three = PrayerListService.buildPlan(homes, 3, now: now);
      expect(numbers(three), [1, 2, 3, 4, 5]);
      expect(three.isTodayDone, isTrue);

      // The neighborhood cycle does not depend on the daily goal.
      for (final plan in [ten, fifteen, three]) {
        expect((plan.cyclePrayed, plan.cycleTotal), (5, 20));
      }
    });

    test('a bigger daily target from Settings gives a longer list', () {
      final homes = [for (var i = 1; i <= 10; i++) household(i)];
      expect(PrayerListService.buildPlan(homes, 3, now: now).today.length, 3);
      expect(PrayerListService.buildPlan(homes, 7, now: now).today.length, 7);
      expect(PrayerListService.buildPlan(homes, 15, now: now).today.length, 10);
    });

    test('today is done once every household on the list is prayed for', () {
      final plan = PrayerListService.buildPlan(
        [
          household(1, isPrayed: true, prayedAt: now),
          household(2, isPrayed: true, prayedAt: now),
          household(3),
        ],
        2,
        now: now,
      );
      expect(numbers(plan), [1, 2]);
      expect(plan.isTodayDone, isTrue);
      expect(plan.isCycleComplete, isFalse);
      expect(plan.daysLeft, 1);
    });

    test('the cycle is complete when everyone has been prayed for', () {
      final earlier = DateTime(2026, 9, 15);
      final plan = PrayerListService.buildPlan(
        [
          household(1, isPrayed: true, prayedAt: earlier),
          household(2, isPrayed: true, prayedAt: earlier),
        ],
        5,
        now: now,
      );
      expect(plan.today, isEmpty);
      expect(plan.isCycleComplete, isTrue);
      expect(plan.isTodayDone, isFalse);
    });

    test('extra prayers are counted apart from today\'s goal', () {
      final homes = [
        for (var i = 1; i <= 10; i++)
          HouseholdModel(
            id: 'h$i',
            number: i,
            residentName: 'R',
            address: 'A',
            isPrayed: i <= 8,
            prayedAt: i <= 8 ? now : null,
          ),
      ];
      final plan = PrayerListService.buildPlan(homes, 5, now: now);
      expect((plan.countedToday, plan.todayGoal, plan.extraToday), (5, 5, 3));
      expect(plan.isTodayDone, isTrue);
      // Tomorrow holds only the 2 neighbors left in the round.
      expect((plan.tomorrowCount, plan.tomorrowIsLast), (2, true));
      expect(plan.needsNewRound, isFalse);
    });

    test('a round finished on an earlier day needs a new round', () {
      final yesterday = now.subtract(const Duration(days: 1));
      HouseholdModel prayed(int i, DateTime at) => HouseholdModel(
        id: 'h$i',
        number: i,
        residentName: 'R',
        address: 'A',
        isPrayed: true,
        prayedAt: at,
      );
      final finishedYesterday = PrayerListService.buildPlan(
        [for (var i = 1; i <= 4; i++) prayed(i, yesterday)],
        5,
        now: now,
      );
      expect(finishedYesterday.isCycleComplete, isTrue);
      expect(finishedYesterday.needsNewRound, isTrue);

      // The day the round is finished is not cut short.
      final finishedToday = PrayerListService.buildPlan(
        [for (var i = 1; i <= 3; i++) prayed(i, yesterday), prayed(4, now)],
        5,
        now: now,
      );
      expect(finishedToday.isCycleComplete, isTrue);
      expect(finishedToday.needsNewRound, isFalse);
    });

    test('no households means an empty plan, not a complete cycle', () {
      final plan = PrayerListService.buildPlan(const [], 5, now: now);
      expect(plan.cycleTotal, 0);
      expect(plan.isCycleComplete, isFalse);
    });
  });

  group('prayer cycle', () {
    final cycleStart = DateTime(2026, 9, 1);

    test('a prayer before the cycle started no longer counts', () {
      expect(
        HouseholdModel.prayedInCycle({
          'isPrayed': true,
          'prayedAt': Timestamp.fromDate(DateTime(2026, 8, 20)),
        }, cycleStart),
        isFalse,
      );
      expect(
        HouseholdModel.prayedInCycle({
          'isPrayed': true,
          'prayedAt': Timestamp.fromDate(DateTime(2026, 9, 2)),
        }, cycleStart),
        isTrue,
      );
    });

    test('without a cycle every prayer counts', () {
      expect(HouseholdModel.prayedInCycle({'isPrayed': true}, null), isTrue);
      expect(HouseholdModel.prayedInCycle({'isPrayed': false}, null), isFalse);
      expect(HouseholdModel.prayedInCycle(null, null), isFalse);
    });
  });

  group('HouseholdModel', () {
    test('status comparison ignores non-status fields', () {
      final a = household(1);
      expect(a.hasSameStatusAs(a.copyWith(residentName: 'Other')), isTrue);
      expect(a.hasSameStatusAs(a.copyWith(isVisited: true)), isFalse);
    });

    test('clears follow-up date in Firestore data when follow-up is off', () {
      final data = household(1)
          .copyWith(hasFollowUp: false, followUpDate: '01/01/2026')
          .toStatusFirestore();
      expect(data['followUpDate'], isNull);
    });
  });

  group('UserModel', () {
    test('has location only when both coordinates are set', () {
      final user = UserModel(id: 'u', fullName: 'A', email: 'a@b.co');
      expect(user.hasLocation, isFalse);
      expect(
        user.copyWith(latitude: 40.8, longitude: -74.0).hasLocation,
        isTrue,
      );
    });

    test('does not persist derived stats to Firestore', () {
      final data = UserModel(
        id: 'u',
        fullName: 'A',
        email: 'a@b.co',
      ).toFirestore();
      expect(data.containsKey('homesPrayed'), isFalse);
      expect(data.containsKey('id'), isFalse);
    });
  });

  test('defaultFollowUpDate is one week out as MM/dd/yyyy', () {
    expect(defaultFollowUpDate(DateTime(2026, 12, 28)), '01/04/2027');
  });

  test('FirebaseErrorMapper gives friendly auth messages', () {
    expect(
      FirebaseErrorMapper.message(
        FirebaseAuthException(code: 'invalid-verification-code'),
      ),
      'The verification code is incorrect.',
    );
    expect(FirebaseErrorMapper.message(const AppException('Custom')), 'Custom');
  });
}
