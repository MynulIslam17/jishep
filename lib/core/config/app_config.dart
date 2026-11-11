class AppConfig {
  AppConfig._();

  static const String environment = 'development';
  static const bool isProduction = false;
  static const String appVersion = '1.0.0';
  static const int buildNumber = 1;

  // --- Phone sign-in ---
  // Off for now: hides phone sign-in (Sign In), SMS password reset (Forgot
  // Password) and adding a phone (Edit Profile). The phone code paths stay in
  // place; set to true to bring them back (and re-add phone numbers to the
  // Privacy Policy and store privacy answers, which follow this flag).
  static const bool phoneAuthEnabled = false;
}
