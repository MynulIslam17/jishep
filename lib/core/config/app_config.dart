class AppConfig {
  AppConfig._();

  static const String environment = 'development';
  static const bool isProduction = false;
  static const String appVersion = '1.0.0';
  static const int buildNumber = 1;

  /// Console logs for Firestore, Auth, HTTP, and geocoding. Debug builds only.
  static const bool logApiOperations = true;
}
