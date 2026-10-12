import 'package:get/get.dart';
import 'package:gps_cielo/core/services/location_service.dart';
import 'package:gps_cielo/features/auth/domain/services/auth_service.dart';
import 'package:gps_cielo/features/auth/presentation/controllers/auth_controller.dart';
import 'package:gps_cielo/features/auth/presentation/controllers/forgot_password_controller.dart';
import 'package:gps_cielo/features/auth/presentation/controllers/location_setup_controller.dart';
import 'package:gps_cielo/features/auth/presentation/controllers/otp_verification_controller.dart';
import 'package:gps_cielo/features/auth/presentation/controllers/reset_password_controller.dart';
import 'package:gps_cielo/features/auth/presentation/controllers/sign_in_controller.dart';
import 'package:gps_cielo/features/auth/presentation/controllers/sign_up_controller.dart';

// Auth repositories, services and the global AuthController are registered
// permanently in AppBinding.

class SignInBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<SignInController>(
      () => SignInController(
        Get.find<AuthService>(),
        Get.find<AuthController>(),
      ),
    );
  }
}

class SignUpBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<SignUpController>(
      () => SignUpController(
        Get.find<AuthService>(),
        Get.find<AuthController>(),
      ),
    );
  }
}

class ForgotPasswordBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<ForgotPasswordController>(
      () => ForgotPasswordController(
        Get.find<AuthService>(),
        Get.find<AuthController>(),
      ),
    );
  }
}

class OtpVerificationBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<OtpVerificationController>(
      () => OtpVerificationController(
        Get.find<AuthService>(),
        Get.find<AuthController>(),
      ),
    );
  }
}

class ResetPasswordBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<ResetPasswordController>(
      () => ResetPasswordController(
        Get.find<AuthService>(),
      ),
    );
  }
}

class LocationSetupBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<LocationSetupController>(
      () => LocationSetupController(
        Get.find<AuthService>(),
        Get.find<AuthController>(),
        Get.find<LocationService>(),
      ),
    );
  }
}

class AuthBinding extends Bindings {
  @override
  void dependencies() {
    SignInBinding().dependencies();
    SignUpBinding().dependencies();
  }
}
