/// Firestore collection names and document paths.
///
/// Data layout:
/// - `users/{uid}` — profile, home location and prayer preferences
/// - `users/{uid}/household_status/{householdId}` — the user's own prayed /
///   visited / invited / follow-up state for a shared household
/// - `users/{uid}/notifications/{id}` — in-app notifications
/// - `users/{uid}/devices/{fcmToken}` — this user's devices for push
///   notifications (one document per FCM token, so never duplicated)
/// - `users/{uid}/prayer_log/{roundId}_{householdId}` — append-only prayer
///   history: one event per home per round (a new round never overwrites)
/// - `users/{uid}/prayer_rounds/{roundId}` — the homes in each round
/// - `households/{id}` — shared household directory (admin managed)
/// - `support_messages/{id}` — messages sent from Contact Support
abstract final class FirestorePaths {
  static const String users = 'users';
  static const String households = 'households';
  static const String householdStatus = 'household_status';
  static const String notifications = 'notifications';
  static const String supportMessages = 'support_messages';
  static const String devices = 'devices';
  static const String prayerLog = 'prayer_log';
  static const String prayerRounds = 'prayer_rounds';

  static String user(String uid) => '$users/$uid';
  static String userHouseholdStatus(String uid) =>
      '$users/$uid/$householdStatus';
  static String userNotifications(String uid) => '$users/$uid/$notifications';
  static String userDevices(String uid) => '$users/$uid/$devices';
  static String userPrayerLog(String uid) => '$users/$uid/$prayerLog';
  static String userPrayerRounds(String uid) => '$users/$uid/$prayerRounds';

  /// The round that started at [cycleStart] (`prayerCycleStartedAt`);
  /// `r0` is the first round (no start recorded).
  static String roundId(DateTime? cycleStart) =>
      cycleStart == null ? 'r0' : 'r${cycleStart.millisecondsSinceEpoch}';

  /// One prayer event: the same home in the same round has one event.
  static String prayerEventId(String roundId, String householdId) =>
      '${roundId}_$householdId';
}
