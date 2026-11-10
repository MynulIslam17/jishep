// ignore_for_file: subtype_of_sealed_class
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gps_cielo/core/utils/firebase_error_mapper.dart';
import 'package:gps_cielo/features/auth/data/repositories/auth_repository.dart';

/// Records the provider passed to Firebase and fails as told.
class _Auth implements FirebaseAuth {
  AuthProvider? provider;
  Object? error;

  @override
  Future<UserCredential> signInWithProvider(AuthProvider provider) async {
    this.provider = provider;
    throw error ?? StateError('no result configured');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late _Auth firebase;
  late AuthRepository repo;

  setUp(() {
    firebase = _Auth();
    repo = AuthRepository(auth: firebase);
  });

  test('asks Apple for the email and the name', () async {
    firebase.error = FirebaseAuthException(code: 'canceled');
    await repo.signInWithApple();
    final provider = firebase.provider as AppleAuthProvider;
    expect(provider.providerId, 'apple.com');
    expect(provider.scopes, containsAll(['email', 'name']));
  });

  test('closing the Apple sheet is a cancellation, not an error', () async {
    for (final code in ['canceled', 'cancelled', 'web-context-canceled']) {
      firebase.error = FirebaseAuthException(code: code);
      expect(await repo.signInWithApple(), isNull, reason: code);
    }
    firebase.error = FirebaseAuthException(
      code: 'unknown',
      message:
          'The operation couldn’t be completed. '
          '(com.apple.AuthenticationServices.AuthorizationError error 1001.)',
    );
    expect(await repo.signInWithApple(), isNull);
  });

  test('real failures are passed on with a readable message', () async {
    for (final code in ['failed', 'invalid-response', 'not-handled']) {
      firebase.error = FirebaseAuthException(code: code);
      await expectLater(
        repo.signInWithApple(),
        throwsA(
          isA<FirebaseAuthException>().having(
            FirebaseErrorMapper.message,
            'message',
            'Sign in with Apple did not complete. Please try again.',
          ),
        ),
        reason: code,
      );
    }
    firebase.error = FirebaseAuthException(
      code: 'account-exists-with-different-credential',
    );
    await expectLater(
      repo.signInWithApple(),
      throwsA(
        isA<FirebaseAuthException>().having(
          FirebaseErrorMapper.message,
          'message',
          contains('different sign-in method'),
        ),
      ),
    );
  });

  // Formats from firebase_auth 6.7.0 AuthErrors.swift
  // (convertAppleAuthorizationErrorToFlutterError): code "unknown",
  // message "<localizedDescription> (Domain=<domain> Code=<code>)".
  String native(int code) =>
      'The operation couldn’t be completed. '
      '(com.apple.AuthenticationServices.AuthorizationError error $code.) '
      '(Domain=com.apple.AuthenticationServices.AuthorizationError '
      'Code=$code)';

  test('no Apple Account (error 1000) gives a readable message', () async {
    firebase.error = FirebaseAuthException(
      code: 'unknown',
      message: native(1000),
    );
    await expectLater(
      repo.signInWithApple(),
      throwsA(
        isA<AppException>().having(
          FirebaseErrorMapper.message,
          'message',
          AuthRepository.appleUnavailableMessage,
        ),
      ),
    );
  });

  test('a cancel reported as unknown/Code=1001 is still a cancel', () async {
    firebase.error = FirebaseAuthException(
      code: 'unknown',
      message:
          '(Domain=com.apple.AuthenticationServices.AuthorizationError '
          'Code=1001)',
    );
    expect(await repo.signInWithApple(), isNull);
  });

  test('other unknown errors are not mistaken for Apple ones', () async {
    firebase.error = FirebaseAuthException(
      code: 'unknown',
      message: 'Something else (Domain=NSURLErrorDomain Code=1000)',
    );
    await expectLater(
      repo.signInWithApple(),
      throwsA(isA<FirebaseAuthException>()),
    );
  });

  test('offered on iOS only', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    expect(repo.appleSignInAvailable, isTrue);
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    expect(repo.appleSignInAvailable, isFalse);
    debugDefaultTargetPlatformOverride = null;
  });
}
