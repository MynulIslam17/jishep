import 'package:get/get.dart';
import 'package:gps_cielo/features/auth/presentation/controllers/auth_controller.dart';
import 'package:gps_cielo/features/splash/data/models/splash_model.dart';
import 'package:gps_cielo/features/splash/domain/services/splash_service.dart';
import 'package:gps_cielo/routes/app_routes.dart';

class SplashController extends GetxController {
  SplashController(this._splashService, this._authController);

  final SplashService _splashService;
  final AuthController _authController;
  late final SplashModel splashData = _splashService.getSplashData();

  @override
  void onInit() {
    super.onInit();
    _startTimerAndNavigate();
  }

  /// Routes to MainNav / Location Setup when signed in, otherwise Onboarding.
  Future<void> _startTimerAndNavigate() async {
    await Future.delayed(const Duration(milliseconds: 2600));

    if (!_authController.isAuthenticated) {
      Get.offAllNamed(AppRoutes.onboarding);
      return;
    }

    try {
      final profile = await _authController.loadCurrentProfile();
      if (profile == null) {
        Get.offAllNamed(AppRoutes.onboarding);
        return;
      }
      Get.offAllNamed(
        profile.hasLocation ? AppRoutes.mainNav : AppRoutes.locationSetup,
      );
    } catch (_) {
      // Offline or profile unreadable: the session is still valid.
      Get.offAllNamed(AppRoutes.mainNav);
    }
  }
}
