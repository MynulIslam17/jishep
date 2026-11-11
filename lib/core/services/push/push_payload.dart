import 'package:gps_cielo/features/notifications/data/models/notification_model.dart';
import 'package:gps_cielo/routes/app_routes.dart';

/// The data part of a push notification, checked before the app acts on it.
///
/// A sender may put these keys in the FCM `data` map:
///  * `type` — one of [NotificationType] (`prayerReminder`, `followUpDue`,
///    `milestone`, `scripture`, `churchNews`);
///  * `route` — where a tap opens; only [allowedRoutes] are accepted;
///  * `householdId` — optional, the household the message is about.
///
/// Anything else is ignored. A payload never grants access to anything: the
/// screen it opens loads the signed-in user's own data, as always.
class PushPayload {
  final NotificationType? type;

  /// The screen a tap opens (always one of [allowedRoutes]).
  final String route;
  final String? householdId;

  const PushPayload({required this.route, this.type, this.householdId});

  /// Screens a notification may open: the main tabs and the inbox.
  static const Set<String> allowedRoutes = {
    AppRoutes.home,
    AppRoutes.neighborhood,
    AppRoutes.prayerList,
    AppRoutes.followUp,
    AppRoutes.profile,
    AppRoutes.notifications,
  };

  static PushPayload fromData(Map<String, dynamic> data) {
    final typeName = data['type']?.toString();
    NotificationType? type;
    for (final t in NotificationType.values) {
      if (t.name == typeName) type = t;
    }
    final requested = (data['route'] ?? data['actionRoute'])?.toString();
    final route = requested != null && allowedRoutes.contains(requested)
        ? requested
        : defaultRouteFor(type);
    final householdId = data['householdId']?.toString();
    return PushPayload(
      type: type,
      route: route,
      householdId:
          householdId == null || householdId.isEmpty || householdId.length > 128
          ? null
          : householdId,
    );
  }

  /// Where a notification of [type] opens when it names no (valid) route.
  static String defaultRouteFor(NotificationType? type) => switch (type) {
    NotificationType.prayerReminder => AppRoutes.prayerList,
    NotificationType.milestone => AppRoutes.prayerList,
    NotificationType.followUpDue => AppRoutes.followUp,
    _ => AppRoutes.notifications,
  };
}
