abstract final class AppValidator {
  static final RegExp _emailPattern = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

  static String? required(String? value, {String fieldName = 'This field'}) {
    if (value == null || value.trim().isEmpty) {
      return '$fieldName is required';
    }
    return null;
  }

  static String? name(String? value) {
    final requiredError = required(value, fieldName: 'Name');
    if (requiredError != null) return requiredError;
    if (value!.trim().length < 2) return 'Enter a valid name';
    return null;
  }

  static String? email(String? value) {
    final requiredError = required(value, fieldName: 'Email');
    if (requiredError != null) return requiredError;
    if (!_emailPattern.hasMatch(value!.trim())) return 'Enter a valid email address';
    return null;
  }

  static String? password(String? value, {int minLength = 6}) {
    final requiredError = required(value, fieldName: 'Password');
    if (requiredError != null) return requiredError;
    if (value!.length < minLength) {
      return 'Password must be at least $minLength characters';
    }
    return null;
  }

  static String? confirmPassword(String? value, String password) {
    final requiredError = required(value, fieldName: 'Confirm password');
    if (requiredError != null) return requiredError;
    if (value != password) return 'Passwords do not match';
    return null;
  }

  static String? phone(String? value) {
    final requiredError = required(value, fieldName: 'Phone number');
    if (requiredError != null) return requiredError;
    final digits = value!.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 7 || digits.length > 15) {
      return 'Enter a valid phone number';
    }
    return null;
  }
}
