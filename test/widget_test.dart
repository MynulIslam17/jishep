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
  group('PrayerListService.buildTodayList', () {
    final now = DateTime(2026, 9, 17, 15);

    test('fills the daily target with unprayed households, nearest first', () {
      final list = PrayerListService.buildTodayList(
        [household(1), household(2), household(3), household(4)],
        3,
        now: now,
      );
      expect(list.map((h) => h.number), [1, 2, 3]);
    });

    test('keeps households prayed today and skips ones prayed earlier', () {
      final list = PrayerListService.buildTodayList(
        [
          household(1, isPrayed: true, prayedAt: DateTime(2026, 9, 10)),
          household(2, isPrayed: true, prayedAt: DateTime(2026, 9, 17, 9)),
          household(3),
          household(4),
        ],
        2,
        now: now,
      );
      expect(list.map((h) => h.number), [2, 3]);
    });

    test('praying for a household does not change the list size', () {
      final before = PrayerListService.buildTodayList(
        [household(1), household(2), household(3)],
        2,
        now: now,
      );
      final after = PrayerListService.buildTodayList(
        [household(1, isPrayed: true, prayedAt: now), household(2), household(3)],
        2,
        now: now,
      );
      expect(before.map((h) => h.number), [1, 2]);
      expect(after.map((h) => h.number), [1, 2]);
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
      final data = UserModel(id: 'u', fullName: 'A', email: 'a@b.co')
          .toFirestore();
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
    expect(
      FirebaseErrorMapper.message(const AppException('Custom')),
      'Custom',
    );
  });
}
