import 'package:get/get.dart';
import 'package:gps_cielo/core/data/household_repository.dart';
import 'package:gps_cielo/core/data/user_repository.dart';
import 'package:gps_cielo/core/services/address_suggestion_service.dart';
import 'package:gps_cielo/core/services/household_store.dart';
import 'package:gps_cielo/core/services/location_service.dart';
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
    Get.put<LocationService>(LocationService(), permanent: true);
    Get.put<AddressSuggestionService>(
      AddressSuggestionService(),
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

    // 4. Global Auth Stack (Permanent)
    final authRepository = Get.put<AuthRepository>(
      AuthRepository(),
      permanent: true,
    );

    final authService = Get.put<AuthService>(
      AuthService(authRepository, userRepository),
      permanent: true,
    );

    Get.put<AuthController>(
      AuthController(authService, userRepository, householdStore),
      permanent: true,
    );
  }
}

typedef AppBindings = AppBinding;
