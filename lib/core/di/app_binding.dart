import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:gps_cielo/core/data/device_token_repository.dart';
import 'package:gps_cielo/core/data/household_repository.dart';
import 'package:gps_cielo/core/data/user_repository.dart';
import 'package:gps_cielo/core/services/address_suggestion_service.dart';
import 'package:gps_cielo/core/services/home_address_service.dart';
import 'package:gps_cielo/core/services/household_store.dart';
import 'package:gps_cielo/core/services/location_service.dart';
import 'package:gps_cielo/core/services/push/push_messaging_client.dart';
import 'package:gps_cielo/core/services/push/push_notification_service.dart';
import 'package:gps_cielo/core/storage/local_storage_service.dart';
import 'package:gps_cielo/features/auth/data/repositories/auth_repository.dart';
import 'package:gps_cielo/features/auth/domain/services/auth_service.dart';
import 'package:gps_cielo/features/auth/presentation/controllers/auth_controller.dart';
import 'package:gps_cielo/features/notifications/data/repositories/notification_repository.dart';

class AppBinding extends Bindings {
  @override
  void dependencies() {
    // 1. Core services (Permanent)
    Get.put<LocalStorageService>(LocalStorageService(), permanent: true);
    final addressSearch = Get.put<AddressSuggestionService>(
      AddressSuggestionService(),
      permanent: true,
    );
    Get.put<LocationService>(
      LocationService(addressSearch: addressSearch),
      permanent: true,
    );

    // 2. Firebase repositories (Permanent)
    final userRepository = Get.put<UserRepository>(
      UserRepository(),
      permanent: true,
    );
    final notificationRepository = Get.put<NotificationRepository>(
      NotificationRepository(),
      permanent: true,
    );
    final householdRepository = Get.put<HouseholdRepository>(
      HouseholdRepository(),
      permanent: true,
    );

    // 3. Shared household state (Permanent)
    final householdStore = Get.put<HouseholdStore>(
      HouseholdStore(householdRepository, notificationRepository),
      permanent: true,
    );
    Get.put<HomeAddressService>(
      HomeAddressService(userRepository, householdStore),
      permanent: true,
    );

    // 4. Global Auth Stack (Permanent)
    final authRepository = Get.put<AuthRepository>(
      AuthRepository(),
      permanent: true,
    );

    final authService = Get.put<AuthService>(
      AuthService(authRepository, userRepository),
      permanent: true,
    );

    final authController = Get.put<AuthController>(
      AuthController(authService, userRepository, householdStore),
      permanent: true,
    );

    // 5. Push notifications (Firebase Cloud Messaging)
    final client = FirebasePushMessagingClient();
    final isIOS = defaultTargetPlatform == TargetPlatform.iOS;
    final push = Get.put<PushNotificationService>(
      PushNotificationService(
        client,
        DeviceTokenRepository(),
        authController.currentUser,
        platform: isIOS ? 'ios' : 'android',
        showForegroundInApp: !isIOS,
      ),
      permanent: true,
    );
    authController.addBeforeSignOut(push.unregister);
    if (isIOS) client.configureForeground().catchError((_) {});
    push.start();
  }
}

typedef AppBindings = AppBinding;
