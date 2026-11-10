import 'package:firebase_auth/firebase_auth.dart';
import 'package:gps_cielo/core/data/user_repository.dart';
import 'package:gps_cielo/core/models/user_model.dart';
import 'package:gps_cielo/core/utils/firebase_error_mapper.dart';
import 'package:gps_cielo/features/auth/data/repositories/auth_repository.dart';

/// Why an SMS code is being verified.
enum OtpPurpose {
  /// Sign in to an existing account with phone number.
  signIn,

  /// Prove ownership of the account's phone before setting a new password.
  resetPassword,

  /// Add and verify a phone later, from Edit Profile.
  addPhone,
}

class AuthService {
  final AuthRepository _authRepository;
  final UserRepository _userRepository;

  AuthService(this._authRepository, this._userRepository);

  User? get firebaseUser => _authRepository.currentUser;

  Stream<User?> authStateChanges() => _authRepository.authStateChanges();

  Stream<PhoneAuthCredential> get autoVerifiedCredentials =>
      _authRepository.autoVerifiedCredentials;

  Future<UserModel> signInWithEmail(String email, String password) async {
    final credential = await _authRepository.signInWithEmail(email, password);
    return ensureProfile(credential.user!);
  }

  /// Creates the email/password account and its Firestore profile.
  /// The address is confirmed next with [sendEmailVerification].
  ///
  /// If the same email is already signed in (the user came back to the
  /// form), the existing account is reused.
  Future<UserModel> register({
    required String fullName,
    required String email,
    required String password,
  }) async {
    final existing = _authRepository.currentUser;
    final User user;
    if (existing != null &&
        existing.email?.toLowerCase() == email.trim().toLowerCase()) {
      user = existing;
    } else {
      if (existing != null) await _authRepository.signOut();
      final credential = await _authRepository.createAccount(email, password);
      user = credential.user!;
    }

    await _authRepository.updateDisplayName(fullName.trim());

    // A phone can be added and verified later from Edit Profile.
    final profile = UserModel(
      id: user.uid,
      fullName: fullName.trim(),
      email: email.trim(),
      phone: user.phoneNumber,
    );
    return _userRepository.createUser(profile);
  }

  Future<SmsVerificationResult> sendPhoneCode(
    String phone, {
    int? resendToken,
  }) {
    return _authRepository.sendPhoneCode(phone, resendToken: resendToken);
  }

  PhoneAuthCredential credentialFromCode({
    required String verificationId,
    required String smsCode,
  }) {
    return _authRepository.phoneCredential(
      verificationId: verificationId,
      smsCode: smsCode,
    );
  }

  /// Signs in with a verified phone credential. Only numbers that belong to
  /// an existing account are accepted.
  Future<UserModel> signInWithPhone(PhoneAuthCredential credential) async {
    final user = await _signInRegisteredPhone(credential);
    return ensureProfile(user);
  }

  /// Links the verified phone number to the account that is signed in.
  Future<void> linkPhone(PhoneAuthCredential credential, String phone) async {
    final user = _authRepository.currentUser;
    if (user == null) throw const AppException('Your session has expired.');

    try {
      await _authRepository.linkCredential(credential);
    } on FirebaseAuthException catch (e) {
      final alreadyLinkedHere =
          e.code == 'provider-already-linked' && user.phoneNumber == phone;
      if (!alreadyLinkedHere) rethrow;
    }
    await _userRepository.updateFields(user.uid, {'phone': phone});
  }

  /// Signs the user in with their phone so the password can be changed.
  Future<void> verifyPhoneForPasswordReset(
    PhoneAuthCredential credential,
  ) async {
    final user = await _signInRegisteredPhone(credential);
    final hasPassword = user.providerData.any(
      (info) => info.providerId == 'password',
    );
    if (!hasPassword) {
      await _authRepository.signOut();
      throw const AppException(
        'This account does not use a password. Sign in with Google, Apple '
        'or your phone number.',
      );
    }
  }

  /// Email/password accounts must confirm their address before using the
  /// app. Google and Apple accounts are verified by their provider.
  bool get needsEmailVerification {
    final user = _authRepository.currentUser;
    if (user == null) return false;
    final providers = _authRepository.providerIds;
    return providers.contains('password') &&
        !providers.contains('google.com') &&
        !providers.contains('apple.com') &&
        !user.emailVerified;
  }

  /// Sends (or resends) the verification link to the signed-in email.
  Future<void> sendEmailVerification() =>
      _authRepository.sendEmailVerification();

  /// Reloads the account and reports whether the email is now verified.
  Future<bool> checkEmailVerified() async {
    final user = await _authRepository.reloadUser();
    return user?.emailVerified ?? false;
  }

  /// Emails a reset link for email/password accounts.
  Future<void> sendPasswordResetEmail(String email) =>
      _authRepository.sendPasswordResetEmail(email);

  /// Sets a new password and signs out so the user signs in again with it.
  Future<void> resetPassword(String newPassword) async {
    await _authRepository.updatePassword(newPassword);
    await _authRepository.signOut();
  }

  /// Returns null when the user cancels the Google dialog.
  Future<UserModel?> signInWithGoogle() async {
    final credential = await _authRepository.signInWithGoogle();
    if (credential == null) return null;
    return ensureProfile(credential.user!);
  }

  /// Whether native Sign in with Apple can be offered on this device.
  bool get appleSignInAvailable => _authRepository.appleSignInAvailable;

  /// Returns null when the user cancels the Apple sheet.
  ///
  /// Apple sends the name only the first time the user authorizes the app
  /// (it becomes the Firebase display name), and the email may be a private
  /// relay address; both are stored as given. A returning user keeps their
  /// existing profile — one Firestore document per account.
  Future<UserModel?> signInWithApple() async {
    final credential = await _authRepository.signInWithApple();
    if (credential == null) return null;
    return ensureProfile(credential.user!);
  }

  /// Loads the Firestore profile for [user], creating it on first sign in.
  /// An existing profile without a name takes the provider's name when one
  /// is available now (e.g. Apple shares it once).
  Future<UserModel> ensureProfile(User user) async {
    final displayName = user.displayName?.trim() ?? '';
    final existing = await _userRepository.getUser(user.uid);
    if (existing != null) {
      if (existing.fullName.trim().isEmpty && displayName.isNotEmpty) {
        await _userRepository.updateFields(user.uid, {'fullName': displayName});
        return existing.copyWith(fullName: displayName);
      }
      return existing;
    }

    final profile = UserModel(
      id: user.uid,
      fullName: displayName,
      email: user.email ?? '',
      phone: user.phoneNumber,
      avatarUrl: user.photoURL,
    );
    return _userRepository.createUser(profile);
  }

  /// Saves the home chosen in Location setup with the search range and
  /// daily prayer goal picked there.
  Future<void> updateLocation({
    required String address,
    required double latitude,
    required double longitude,
    required double searchRadiusKm,
    required int dailyPrayerTarget,
  }) {
    final user = _authRepository.currentUser;
    if (user == null) throw const AppException('You are not signed in.');
    return _userRepository.updateFields(user.uid, {
      'address': address,
      'latitude': latitude,
      'longitude': longitude,
      'searchRadiusKm': searchRadiusKm,
      'dailyPrayerTarget': dailyPrayerTarget,
    });
  }

  Future<void> signOut() => _authRepository.signOut();

  /// Whether deleting the account must be confirmed with a password.
  bool get accountUsesPassword =>
      _authRepository.providerIds.contains('password');

  /// Confirms the user's identity right before deleting the account, as
  /// Firebase requires a recent sign-in. Returns false if cancelled.
  Future<bool> reauthenticateForDeletion({String? password}) async {
    final user = _authRepository.currentUser;
    if (user == null) throw const AppException('You are not signed in.');

    final providers = _authRepository.providerIds;
    if (providers.contains('password')) {
      if (password == null || password.isEmpty) {
        throw const AppException('Please enter your password.');
      }
      await _authRepository.reauthenticateWithPassword(password);
      return true;
    }
    if (providers.contains('google.com')) {
      return _authRepository.reauthenticateWithGoogle();
    }
    if (providers.contains('apple.com') && appleSignInAvailable) {
      final result = await _authRepository.reauthenticateWithApple();
      if (result == null) return false;
      _appleAuthorizationCode = result.authorizationCode;
      return true;
    }

    final lastSignIn = user.metadata.lastSignInTime;
    final recent =
        lastSignIn != null &&
        DateTime.now().difference(lastSignIn) < const Duration(minutes: 5);
    if (!recent) {
      throw const AppException(
        'For security, please log out, sign in again, then delete your account.',
      );
    }
    return true;
  }

  /// Apple's code from the confirmation before deletion, used to revoke the
  /// app's Apple tokens.
  String? _appleAuthorizationCode;

  /// Which account the user confirms with before deletion (for the dialog):
  /// `password`, `google.com`, `apple.com` or null (recent sign-in).
  String? get deletionConfirmationProvider {
    final providers = _authRepository.providerIds;
    for (final p in const ['password', 'google.com', 'apple.com']) {
      if (providers.contains(p)) return p;
    }
    return null;
  }

  /// Permanently deletes the user's Firestore data and Firebase account.
  /// Call [reauthenticateForDeletion] first.
  Future<void> deleteAccount() async {
    final user = _authRepository.currentUser;
    if (user == null) throw const AppException('You are not signed in.');

    // Apple requires apps to revoke their Apple tokens when the account is
    // deleted. A failed revocation does not block the deletion itself.
    final code = _appleAuthorizationCode;
    _appleAuthorizationCode = null;
    if (code != null && code.isNotEmpty) {
      try {
        await _authRepository.revokeAppleToken(code);
      } catch (_) {}
    }

    await _userRepository.deleteUserData(user.uid);
    await _authRepository.deleteCurrentUser();
    await _authRepository.signOut();
  }

  Future<User> _signInRegisteredPhone(PhoneAuthCredential credential) async {
    final result = await _authRepository.signInWithCredential(credential);
    if (result.additionalUserInfo?.isNewUser ?? false) {
      await _authRepository.deleteCurrentUser();
      await _authRepository.signOut();
      throw const AppException(
        'No account is registered with this phone number. Please sign up first.',
      );
    }
    return result.user!;
  }
}
