/// Firestore collection names and document paths.
///
/// Data layout:
/// - `users/{uid}` — profile, home location and prayer preferences
/// - `users/{uid}/household_status/{householdId}` — the user's own prayed /
///   visited / invited / follow-up state for a shared household
/// - `users/{uid}/notifications/{id}` — in-app notifications
/// - `households/{id}` — shared household directory (admin managed)
/// - `support_messages/{id}` — messages sent from Contact Support
abstract final class FirestorePaths {
  static const String users = 'users';
  static const String households = 'households';
  static const String householdStatus = 'household_status';
  static const String notifications = 'notifications';
  static const String supportMessages = 'support_messages';

  static String user(String uid) => '$users/$uid';
  static String userHouseholdStatus(String uid) => '$users/$uid/$householdStatus';
  static String userNotifications(String uid) => '$users/$uid/$notifications';
}
