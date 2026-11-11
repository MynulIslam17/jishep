import 'package:flutter_test/flutter_test.dart';
import 'package:gps_cielo/core/utils/search_range.dart';
import 'package:gps_cielo/features/home/presentation/controllers/home_controller.dart';

/// One rule ties the tabs together: the neighborhood is the Settings number
/// of homes nearest home, and the daily goal always fits inside it.
void main() {
  group('the daily goal fits the neighborhood', () {
    test('a goal within the neighborhood is kept', () {
      expect(SearchRange.clampGoal(5, 10), 5);
      expect(SearchRange.clampGoal(10, 10), 10);
      expect(SearchRange.clampGoal(15, 25), 15);
    });

    test('a goal above it drops to the largest that fits', () {
      expect(SearchRange.clampGoal(15, 10), 10);
      expect(SearchRange.clampGoal(10, 5), 5);
      expect(SearchRange.clampGoal(15, 5), 5);
    });

    test('every neighborhood size leaves at least one goal to pick', () {
      for (final homes in SearchRange.options) {
        expect(
          SearchRange.goalOptions.where((g) => g <= homes),
          isNotEmpty,
          reason: '$homes homes',
        );
      }
    });
  });

  group('changing the neighborhood on Home', () {
    test('says which tabs change', () {
      const change = NeighborhoodSizeChange(
        homes: 20,
        previousHomes: 10,
        dailyGoal: 5,
        previousDailyGoal: 5,
      );
      expect(change.lowersGoal, isFalse);
      expect(
        change.dialogMessage,
        'Home, Neighborhood and your prayer rounds will all use the 20 '
        'homes nearest your home (now 10).',
      );
    });

    test('says when the daily goal has to come down', () {
      final change = NeighborhoodSizeChange(
        homes: 5,
        previousHomes: 10,
        dailyGoal: SearchRange.clampGoal(10, 5),
        previousDailyGoal: 10,
      );
      expect(change.lowersGoal, isTrue);
      expect(change.dialogMessage, contains('from 10 to 5 a day'));
    });
  });
}
