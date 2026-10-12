import 'package:firebase_auth/firebase_auth.dart';
import 'package:gps_cielo/core/data/user_repository.dart';
import 'package:gps_cielo/core/models/user_model.dart';
import 'package:gps_cielo/core/utils/firebase_error_mapper.dart';
import 'package:gps_cielo/features/auth/data/repositories/auth_repository.dart';

/// Why an SMS code is being verified.
enum OtpPurpose {
  /// Sign in to an existing account with phone number.
  signIn,

  /// Verify and link the phone number entered during sign up.
  linkPhone,

  /// Prove ownership of the account's phone before setting a new password.
  resetPassword,
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
  ///
  /// If the same email is already signed in (the user came back from the
  /// phone verification step), the existing account is reused.
  Future<UserModel> register({
    required String fullName,
    required String email,
    required String password,
    required String phone,
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

    final profile = UserModel(
      id: user.uid,
      fullName: fullName.trim(),
      email: email.trim(),
      phone: phone,
    );
    await _userRepository.createUser(profile);
    return profile;
  }

  Future<SmsVerificationResult> sendPhoneCode(String phone, {int? resendToken}) {
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
    final hasPassword =
        user.providerData.any((info) => info.providerId == 'password');
    if (!hasPassword) {
      await _authRepository.signOut();
      throw const AppException(
        'This account does not use a password. Sign in with Google or your phone number.',
      );
    }
  }

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

  /// Loads the Firestore profile for [user], creating it on first sign in.
  Future<UserModel> ensureProfile(User user) async {
    final existing = await _userRepository.getUser(user.uid);
    if (existing != null) return existing;

    final profile = UserModel(
      id: user.uid,
      fullName: user.displayName ?? '',
      email: user.email ?? '',
      phone: user.phoneNumber,
      avatarUrl: user.photoURL,
    );
    await _userRepository.createUser(profile);
    return profile;
  }

  Future<void> updateLocation({
    required String address,
    required double latitude,
    required double longitude,
    required int radiusHomes,
  }) {
    final user = _authRepository.currentUser;
    if (user == null) throw const AppException('You are not signed in.');
    return _userRepository.updateLocation(
      uid: user.uid,
      address: address,
      latitude: latitude,
      longitude: longitude,
      radiusHomes: radiusHomes,
    );
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

    final lastSignIn = user.metadata.lastSignInTime;
    final recent = lastSignIn != null &&
        DateTime.now().difference(lastSignIn) < const Duration(minutes: 5);
    if (!recent) {
      throw const AppException(
        'For security, please log out, sign in again, then delete your account.',
      );
    }
    return true;
  }

  /// Permanently deletes the user's Firestore data and Firebase account.
  /// Call [reauthenticateForDeletion] first.
  Future<void> deleteAccount() async {
    final user = _authRepository.currentUser;
    if (user == null) throw const AppException('You are not signed in.');

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
