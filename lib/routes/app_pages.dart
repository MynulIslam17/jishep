import 'package:get/get.dart';
import 'package:gps_cielo/core/di/auth_binding.dart';
import 'package:gps_cielo/core/di/home_binding.dart';
import 'package:gps_cielo/core/di/main_nav_binding.dart';
import 'package:gps_cielo/core/di/neighborhood_binding.dart';
import 'package:gps_cielo/core/di/notification_binding.dart';
import 'package:gps_cielo/core/di/onboarding_binding.dart';
import 'package:gps_cielo/core/di/prayer_list_binding.dart';
import 'package:gps_cielo/core/di/profile_binding.dart';
import 'package:gps_cielo/core/di/splash_binding.dart';
import 'package:gps_cielo/features/auth/presentation/pages/forgot_password_screen.dart';
import 'package:gps_cielo/features/auth/presentation/pages/location_setup_screen.dart';
import 'package:gps_cielo/features/auth/presentation/pages/otp_verification_screen.dart';
import 'package:gps_cielo/features/auth/presentation/pages/reset_password_screen.dart';
import 'package:gps_cielo/features/auth/presentation/pages/sign_in_screen.dart';
import 'package:gps_cielo/features/auth/presentation/pages/sign_up_screen.dart';
import 'package:gps_cielo/features/home/presentation/pages/home_screen.dart';
import 'package:gps_cielo/features/main_nav/presentation/pages/main_nav_screen.dart';
import 'package:gps_cielo/features/neighborhood/presentation/pages/neighborhood_screen.dart';
import 'package:gps_cielo/features/notifications/presentation/pages/notification_screen.dart';
import 'package:gps_cielo/features/onboarding/presentation/pages/onboarding_screen.dart';
import 'package:gps_cielo/features/prayer_list/presentation/pages/prayer_list_screen.dart';
import 'package:gps_cielo/features/profile/presentation/pages/edit_profile_screen.dart';
import 'package:gps_cielo/features/profile/presentation/pages/profile_screen.dart';
import 'package:gps_cielo/features/splash/presentation/pages/splash_screen.dart';
import 'package:gps_cielo/routes/app_routes.dart';

abstract class AppPages {
  static const String initialRoute = AppRoutes.splash;

  static final pages = [
    GetPage(
      name: AppRoutes.splash,
      page: () => const SplashScreen(),
      binding: SplashBinding(),
      transition: Transition.fadeIn,
    ),
    GetPage(
      name: AppRoutes.onboarding,
      page: () => const OnboardingScreen(),
      binding: OnboardingBinding(),
      transition: Transition.fadeIn,
    ),
    GetPage(
      name: AppRoutes.signIn,
      page: () => const SignInScreen(),
      binding: SignInBinding(),
      transition: Transition.fadeIn,
    ),
    GetPage(
      name: AppRoutes.signUp,
      page: () => const SignUpScreen(),
      binding: SignUpBinding(),
      transition: Transition.rightToLeft,
    ),
    GetPage(
      name: AppRoutes.forgotPassword,
      page: () => const ForgotPasswordScreen(),
      binding: ForgotPasswordBinding(),
      transition: Transition.rightToLeft,
    ),
    GetPage(
      name: AppRoutes.otpVerification,
      page: () => const OtpVerificationScreen(),
      binding: OtpVerificationBinding(),
      transition: Transition.rightToLeft,
    ),
    GetPage(
      name: AppRoutes.resetPassword,
      page: () => const ResetPasswordScreen(),
      binding: ResetPasswordBinding(),
      transition: Transition.rightToLeft,
    ),
    GetPage(
      name: AppRoutes.locationSetup,
      page: () => const LocationSetupScreen(),
      binding: LocationSetupBinding(),
      transition: Transition.rightToLeft,
    ),
    GetPage(
      name: AppRoutes.mainNav,
      page: () => const MainNavScreen(),
      binding: MainNavBinding(),
      transition: Transition.fadeIn,
    ),
    GetPage(
      name: AppRoutes.home,
      page: () => const HomeScreen(),
      binding: HomeBinding(),
    ),
    GetPage(
      name: AppRoutes.neighborhood,
      page: () => const NeighborhoodScreen(),
      binding: NeighborhoodBinding(),
    ),
    GetPage(
      name: AppRoutes.prayerList,
      page: () => const PrayerListScreen(),
      binding: PrayerListBinding(),
    ),
    GetPage(
      name: AppRoutes.profile,
      page: () => const ProfileScreen(),
      binding: ProfileBinding(),
    ),
    GetPage(
      name: AppRoutes.editProfile,
      page: () => const EditProfileScreen(),
      transition: Transition.rightToLeft,
    ),
    GetPage(
      name: AppRoutes.notifications,
      page: () => const NotificationScreen(),
      binding: NotificationBinding(),
      transition: Transition.rightToLeft,
    ),
  ];
}
