import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:gps_cielo/core/utils/api_debug_log.dart';
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

/// Thin wrapper around Firebase Authentication and Google Sign-In.
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
    return ApiDebugLog.run(
      'AuthRepository.signInWithEmail',
      () => _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      ),
      details: email.trim(),
    );
  }

  Future<UserCredential> createAccount(String email, String password) {
    return ApiDebugLog.run(
      'AuthRepository.createAccount',
      () => _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      ),
      details: email.trim(),
    );
  }

  /// Starts SMS verification for [phoneNumber] (E.164, e.g. +12015550000).
  Future<SmsVerificationResult> sendPhoneCode(
    String phoneNumber, {
    int? resendToken,
  }) {
    return ApiDebugLog.run(
      'AuthRepository.sendPhoneCode',
      () => _sendPhoneCode(phoneNumber, resendToken: resendToken),
      details: phoneNumber,
    );
  }

  Future<SmsVerificationResult> _sendPhoneCode(
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
    return ApiDebugLog.run(
      'AuthRepository.signInWithCredential',
      () => _auth.signInWithCredential(credential),
      details: credential.providerId,
    );
  }

  Future<UserCredential> linkCredential(AuthCredential credential) {
    final user = _requireUser();
    return ApiDebugLog.run(
      'AuthRepository.linkCredential',
      () => user.linkWithCredential(credential),
      details: credential.providerId,
    );
  }

  Future<void> updatePassword(String newPassword) {
    return ApiDebugLog.run(
      'AuthRepository.updatePassword',
      () => _requireUser().updatePassword(newPassword),
    );
  }

  Future<void> verifyBeforeUpdateEmail(String newEmail) {
    return ApiDebugLog.run(
      'AuthRepository.verifyBeforeUpdateEmail',
      () => _requireUser().verifyBeforeUpdateEmail(newEmail.trim()),
      details: newEmail.trim(),
    );
  }

  Future<void> updateDisplayName(String name) {
    return ApiDebugLog.run(
      'AuthRepository.updateDisplayName',
      () => _requireUser().updateDisplayName(name),
    );
  }

  /// Deletes the current user. Used to undo accounts that were created
  /// implicitly by phone sign-in for numbers that are not registered.
  Future<void> deleteCurrentUser() {
    return ApiDebugLog.run(
      'AuthRepository.deleteCurrentUser',
      () async {
        await _auth.currentUser?.delete();
      },
    );
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
    return ApiDebugLog.run(
      'AuthRepository.reauthenticateWithPassword',
      () => user.reauthenticateWithCredential(
        EmailAuthProvider.credential(email: email, password: password),
      ),
      details: email,
    );
  }

  /// Returns false if the user cancelled the Google dialog.
  Future<bool> reauthenticateWithGoogle() {
    return ApiDebugLog.run('AuthRepository.reauthenticateWithGoogle', () async {
      final user = _requireUser();
      final credential = await _googleCredential();
      if (credential == null) return false;
      await user.reauthenticateWithCredential(credential);
      return true;
    });
  }

  /// Returns null if the user cancelled the Google dialog.
  Future<UserCredential?> signInWithGoogle() {
    return ApiDebugLog.run('AuthRepository.signInWithGoogle', () async {
      final credential = await _googleCredential();
      if (credential == null) return null;
      return _auth.signInWithCredential(credential);
    });
  }

  Future<OAuthCredential?> _googleCredential() async {
    final google = GoogleSignIn.instance;
    try {
      if (!_googleInitialized) {
        await google.initialize(
          clientId: defaultTargetPlatform == TargetPlatform.iOS
              ? DefaultFirebaseOptions.ios.iosClientId
              : null,
          serverClientId: DefaultFirebaseOptions.googleWebClientId,
        );
        _googleInitialized = true;
      } else {
        // A leftover Credential Manager session can fail as "canceled"
        // after the user picks an account.
        await google.signOut().catchError((_) {});
      }

      final account = await google.authenticate();
      final idToken = account.authentication.idToken;
      if (idToken == null) {
        throw const AppException('Google did not return a sign-in token.');
      }
      return GoogleAuthProvider.credential(idToken: idToken);
    } on GoogleSignInException catch (e) {
      debugPrint(
        'GoogleSignInException code=${e.code} description=${e.description} '
        'details=${e.details}',
      );
      if (e.code == GoogleSignInExceptionCode.canceled) {
        return null;
      }
      throw AppException(_googleSignInMessage(e));
    } on FirebaseAuthException {
      rethrow;
    } on AppException {
      rethrow;
    } catch (error) {
      debugPrint('Google Sign-In unexpected error: $error');
      throw const AppException(
        'Google Sign-In failed. Please try again.',
      );
    }
  }

  static String _googleSignInMessage(GoogleSignInException error) {
    switch (error.code) {
      case GoogleSignInExceptionCode.clientConfigurationError:
      case GoogleSignInExceptionCode.providerConfigurationError:
        return 'Google Sign-In is not configured for this app yet. '
            'Add this computer\'s debug SHA-1 in the Firebase console.';
      case GoogleSignInExceptionCode.interrupted:
        return 'Google Sign-In was interrupted. Please try again.';
      case GoogleSignInExceptionCode.uiUnavailable:
        return 'Google Sign-In could not open. Please try again.';
      default:
        return 'Google Sign-In failed. Please try again.';
    }
  }

  Future<void> signOut() {
    return ApiDebugLog.run('AuthRepository.signOut', () async {
      if (_googleInitialized) {
        await GoogleSignIn.instance.signOut().catchError((_) {});
      }
      await _auth.signOut();
    });
  }

  User _requireUser() {
    final user = _auth.currentUser;
    if (user == null) throw const AppException('You are not signed in.');
    return user;
  }
}
