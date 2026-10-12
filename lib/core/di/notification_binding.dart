import 'package:get/get.dart';
import 'package:gps_cielo/features/notifications/data/repositories/notification_repository.dart';
import 'package:gps_cielo/features/notifications/domain/services/notification_service.dart';
import 'package:gps_cielo/features/notifications/presentation/controllers/notification_controller.dart';

class NotificationBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<NotificationService>(
      () => NotificationService(Get.find<NotificationRepository>()),
    );
    Get.lazyPut<NotificationController>(
      () => NotificationController(Get.find<NotificationService>()),
    );
  }
}
