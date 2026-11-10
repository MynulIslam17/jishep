import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:gps_cielo/core/utils/firebase_error_mapper.dart';
import 'package:gps_cielo/firebase_options.dart';

/// Result of starting phone number verification.
sealed class SmsVerificationResult {
  const SmsVerificationResult();
}

/// An SMS code was sent; the user must enter it.
class SmsCodeSent extends SmsVerificationResult {
  final String verificationId;
  final int? resendToken;

  const SmsCodeSent(this.verificationId, this.resendToken);
}

/// Android verified the number instantly without user input.
class SmsAutoVerified extends SmsVerificationResult {
  final PhoneAuthCredential credential;

  const SmsAutoVerified(this.credential);
}

/// Thin wrapper around Firebase Authentication, Google Sign-In and native
/// Sign in with Apple.
class AuthRepository {
  final FirebaseAuth _auth;

  AuthRepository({FirebaseAuth? auth}) : _auth = auth ?? FirebaseAuth.instance;

  bool _googleInitialized = false;

  final _autoVerifiedController =
      StreamController<PhoneAuthCredential>.broadcast();

  /// Credentials auto-retrieved by Android after the code was already sent.
  Stream<PhoneAuthCredential> get autoVerifiedCredentials =>
      _autoVerifiedController.stream;

  User? get currentUser => _auth.currentUser;

  Stream<User?> authStateChanges() => _auth.authStateChanges();

  Future<UserCredential> signInWithEmail(String email, String password) {
    return _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
  }

  Future<UserCredential> createAccount(String email, String password) {
    return _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
  }

  /// Starts SMS verification for [phoneNumber] (E.164, e.g. +12015550000).
  Future<SmsVerificationResult> sendPhoneCode(
    String phoneNumber, {
    int? resendToken,
  }) {
    final completer = Completer<SmsVerificationResult>();

    _auth.verifyPhoneNumber(
      phoneNumber: phoneNumber,
      forceResendingToken: resendToken,
      timeout: const Duration(seconds: 60),
      verificationCompleted: (credential) {
        if (!completer.isCompleted) {
          completer.complete(SmsAutoVerified(credential));
        } else {
          _autoVerifiedController.add(credential);
        }
      },
      verificationFailed: (error) {
        if (!completer.isCompleted) completer.completeError(error);
      },
      codeSent: (verificationId, token) {
        if (!completer.isCompleted) {
          completer.complete(SmsCodeSent(verificationId, token));
        }
      },
      codeAutoRetrievalTimeout: (_) {},
    );

    return completer.future;
  }

  PhoneAuthCredential phoneCredential({
    required String verificationId,
    required String smsCode,
  }) {
    return PhoneAuthProvider.credential(
      verificationId: verificationId,
      smsCode: smsCode,
    );
  }

  Future<UserCredential> signInWithCredential(AuthCredential credential) {
    return _auth.signInWithCredential(credential);
  }

  Future<UserCredential> linkCredential(AuthCredential credential) async {
    final user = _requireUser();
    final result = await user.linkWithCredential(credential);
    // Fresh token with the phone_number claim the Firestore rules check.
    await result.user?.getIdToken(true);
    return result;
  }

  Future<void> updatePassword(String newPassword) {
    return _requireUser().updatePassword(newPassword);
  }

  Future<void> verifyBeforeUpdateEmail(String newEmail) {
    return _requireUser().verifyBeforeUpdateEmail(newEmail.trim());
  }

  /// Emails the signed-in user a link that confirms their address.
  Future<void> sendEmailVerification() {
    return _requireUser().sendEmailVerification();
  }

  /// Fetches the latest account state (e.g. after the email link was
  /// clicked) and returns the refreshed user.
  Future<User?> reloadUser() async {
    final user = _auth.currentUser;
    if (user == null) return null;
    await user.reload();
    final fresh = _auth.currentUser;
    // New token so the email_verified claim is current for Firestore.
    if (fresh?.emailVerified ?? false) await fresh!.getIdToken(true);
    return fresh;
  }

  Future<void> updateDisplayName(String name) {
    return _requireUser().updateDisplayName(name);
  }

  /// Deletes the current user. Used to undo accounts that were created
  /// implicitly by phone sign-in for numbers that are not registered.
  Future<void> deleteCurrentUser() async {
    await _auth.currentUser?.delete();
  }

  /// Sign-in providers linked to the current user, e.g. `password`,
  /// `google.com`, `phone`.
  Set<String> get providerIds =>
      _auth.currentUser?.providerData.map((info) => info.providerId).toSet() ??
      const {};

  Future<void> reauthenticateWithPassword(String password) {
    final user = _requireUser();
    final email = user.email;
    if (email == null) throw const AppException('This account has no email.');
    return user.reauthenticateWithCredential(
      EmailAuthProvider.credential(email: email, password: password),
    );
  }

  /// Returns false if the user cancelled the Google dialog.
  Future<bool> reauthenticateWithGoogle() async {
    final user = _requireUser();
    final credential = await _googleCredential();
    if (credential == null) return false;
    await user.reauthenticateWithCredential(credential);
    return true;
  }

  /// Native Sign in with Apple is offered on iOS only (Android would need
  /// Apple's web flow with a Services ID, which is not set up).
  bool get appleSignInAvailable =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  /// Apple sign-in asking for the email and name. Apple shares the name only
  /// the first time the user authorizes the app, and the email may be a
  /// private relay address ("Hide My Email").
  static AppleAuthProvider appleProvider() => AppleAuthProvider()
    ..addScope('email')
    ..addScope('name');

  /// Whether [error] means the user closed the Apple sheet (FlutterFire
  /// reports ASAuthorizationError.canceled as `canceled`).
  static bool isAppleCancellation(FirebaseAuthException error) {
    const codes = {
      'canceled',
      'cancelled',
      'user-cancelled',
      'web-context-canceled',
      'web-context-cancelled',
    };
    return codes.contains(error.code) ||
        _appleErrorCode(error) == _appleCanceled;
  }

  /// ASAuthorizationError codes (AuthenticationServices).
  static const int _appleUnknown = 1000;
  static const int _appleCanceled = 1001;

  /// The AuthenticationServices error code inside [error], if any.
  /// FlutterFire passes errors it does not map as code `unknown` with the
  /// native code in the message, as "Domain=…AuthorizationError Code=1000"
  /// (or iOS's own text "…AuthorizationError error 1000.").
  static int? _appleErrorCode(FirebaseAuthException error) {
    final match = RegExp(
      r'AuthorizationError (?:Code=|error )(\d+)',
    ).firstMatch(error.message ?? '');
    return match == null ? null : int.tryParse(match.group(1)!);
  }

  /// Whether Apple could not start sign-in at all: no Apple Account on the
  /// device (iOS then asks to sign in in Settings) or Apple's servers could
  /// not be reached.
  static bool isAppleUnavailable(FirebaseAuthException error) =>
      error.code == 'unknown' && _appleErrorCode(error) == _appleUnknown;

  /// Signs in with the native Apple sheet. Returns null if the user
  /// cancelled.
  Future<UserCredential?> signInWithApple() async {
    try {
      return await _auth.signInWithProvider(appleProvider());
    } on FirebaseAuthException catch (e) {
      if (isAppleCancellation(e)) return null;
      if (isAppleUnavailable(e)) {
        throw const AppException(appleUnavailableMessage);
      }
      rethrow;
    }
  }

  static const String appleUnavailableMessage =
      'Sign in with Apple is not available right now. Make sure you are '
      'signed in to your Apple Account in Settings and connected to the '
      'internet, then try again.';

  /// Confirms the current Apple account again (before deleting it). Returns
  /// null if cancelled; otherwise Apple's one-time authorization code, used
  /// to revoke the app's Apple tokens.
  Future<({String? authorizationCode})?> reauthenticateWithApple() async {
    final user = _requireUser();
    try {
      final result = await user.reauthenticateWithProvider(appleProvider());
      return (authorizationCode: result.additionalUserInfo?.authorizationCode);
    } on FirebaseAuthException catch (e) {
      if (isAppleCancellation(e)) return null;
      if (isAppleUnavailable(e)) {
        throw const AppException(appleUnavailableMessage);
      }
      rethrow;
    }
  }

  /// Revokes the app's Apple tokens (required when an Apple account is
  /// deleted).
  Future<void> revokeAppleToken(String authorizationCode) {
    return _auth.revokeTokenWithAuthorizationCode(authorizationCode);
  }

  /// Returns null if the user cancelled the Google dialog.
  Future<UserCredential?> signInWithGoogle() async {
    final credential = await _googleCredential();
    if (credential == null) return null;
    return _auth.signInWithCredential(credential);
  }

  Future<OAuthCredential?> _googleCredential() async {
    final google = GoogleSignIn.instance;
    try {
      if (!_googleInitialized) {
        await google.initialize(
          clientId: defaultTargetPlatform == TargetPlatform.iOS
              ? DefaultFirebaseOptions.currentPlatform.iosClientId
              : null,
        );
        _googleInitialized = true;
      }

      final account = await google.authenticate();
      final idToken = account.authentication.idToken;
      if (idToken == null) {
        throw const AppException('Google did not return a sign-in token.');
      }
      return GoogleAuthProvider.credential(idToken: idToken);
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled ||
          e.code == GoogleSignInExceptionCode.interrupted) {
        return null;
      }
      throw AppException(
        e.code == GoogleSignInExceptionCode.clientConfigurationError
            ? 'Google Sign-In is not configured for this app yet.'
            : 'Google Sign-In failed. Please try again.',
      );
    } on FirebaseAuthException {
      rethrow;
    } on AppException {
      rethrow;
    } catch (_) {
      throw const AppException(
        'Google Sign-In is not configured for this app yet.',
      );
    }
  }

  /// Emails a password reset link (Firebase handles the reset page).
  Future<void> sendPasswordResetEmail(String email) {
    return _auth.sendPasswordResetEmail(email: email.trim());
  }

  Future<void> signOut() async {
    // Also after an app restart: forget the Google account so the next
    // Google sign-in lets the user choose an account again.
    if (_googleInitialized || providerIds.contains('google.com')) {
      try {
        if (!_googleInitialized) {
          await GoogleSignIn.instance.initialize(
            clientId: defaultTargetPlatform == TargetPlatform.iOS
                ? DefaultFirebaseOptions.currentPlatform.iosClientId
                : null,
          );
          _googleInitialized = true;
        }
        await GoogleSignIn.instance.signOut();
      } catch (_) {
        // Firebase sign-out below still ends the session.
      }
    }
    await _auth.signOut();
  }

  User _requireUser() {
    final user = _auth.currentUser;
    if (user == null) throw const AppException('You are not signed in.');
    return user;
  }
}
