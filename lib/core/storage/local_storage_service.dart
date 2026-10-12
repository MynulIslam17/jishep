import 'package:shared_preferences/shared_preferences.dart';

/// Device-only preferences. Account data lives in Firebase.
class LocalStorageService {
  static const String _rememberMeKey = 'remember_me';

  Future<void> setRememberMe(bool remember) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_rememberMeKey, remember);
  }

  Future<bool> isRememberMe() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_rememberMeKey) ?? false;
  }

  Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }
}
