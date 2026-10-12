import 'package:firebase_auth/firebase_auth.dart';

/// Converts Firebase exceptions into short, user-facing messages.
abstract final class FirebaseErrorMapper {
  static String message(Object error) {
    if (error is FirebaseAuthException) return _authMessage(error);
    if (error is FirebaseException) return _firestoreMessage(error);
    if (error is AppException) return error.message;
    return 'Something went wrong. Please try again.';
  }

  static String _authMessage(FirebaseAuthException e) {
    return switch (e.code) {
      'invalid-email' => 'The email address is not valid.',
      'user-disabled' => 'This account has been disabled.',
      'user-not-found' ||
      'wrong-password' ||
      'invalid-credential' ||
      'INVALID_LOGIN_CREDENTIALS' =>
        'Incorrect email or password.',
      'email-already-in-use' => 'An account already exists with this email.',
      'weak-password' => 'Password is too weak. Use at least 8 characters.',
      'operation-not-allowed' =>
        'This sign-in method is not enabled in Firebase.',
      'too-many-requests' =>
        'Too many attempts. Please wait a moment and try again.',
      'network-request-failed' => 'No internet connection.',
      'invalid-phone-number' => 'The phone number is not valid.',
      'invalid-verification-code' => 'The verification code is incorrect.',
      'invalid-verification-id' || 'session-expired' || 'code-expired' =>
        'The verification code has expired. Please request a new one.',
      'quota-exceeded' => 'SMS quota exceeded. Please try again later.',
      'credential-already-in-use' =>
        'This phone number is already linked to another account.',
      'provider-already-linked' =>
        'This phone number is already linked to your account.',
      'account-exists-with-different-credential' =>
        'An account already exists with this email using a different sign-in method.',
      'requires-recent-login' =>
        'For security, please sign in again and retry.',
      'missing-client-identifier' || 'app-not-authorized' =>
        'Phone sign-in is not configured for this app build.',
      _ => e.message ?? 'Authentication failed. Please try again.',
    };
  }

  static String _firestoreMessage(FirebaseException e) {
    return switch (e.code) {
      'permission-denied' => 'You do not have permission to do that.',
      'unavailable' => 'Service unavailable. Check your connection.',
      'not-found' => 'The requested data was not found.',
      _ => e.message ?? 'Something went wrong. Please try again.',
    };
  }
}

/// Application-level error with a message that is safe to show to the user.
class AppException implements Exception {
  final String message;

  const AppException(this.message);

  @override
  String toString() => message;
}
