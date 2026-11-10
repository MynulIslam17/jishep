// ignore_for_file: subtype_of_sealed_class
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gps_cielo/core/data/user_repository.dart';
import 'package:gps_cielo/core/models/user_model.dart';
import 'package:gps_cielo/core/utils/firebase_error_mapper.dart';
import 'package:gps_cielo/features/auth/data/repositories/auth_repository.dart';
import 'package:gps_cielo/features/auth/domain/services/auth_service.dart';

class FakeUser implements User {
  FakeUser(
    this.uid, {
    this.email,
    this.phoneNumber,
    this.displayName,
    this.emailVerified = false,
  });

  @override
  final bool emailVerified;

  @override
  final String uid;
  @override
  final String? email;
  @override
  final String? phoneNumber;
  @override
  final String? displayName;

  @override
  String? get photoURL => null;

  @override
  List<UserInfo> get providerData => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeCredential implements UserCredential {
  FakeCredential(this.user, {bool isNewUser = false})
    : additionalUserInfo = AdditionalUserInfo(isNewUser: isNewUser);

  @override
  final User user;
  @override
  final AdditionalUserInfo additionalUserInfo;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeAuthRepository implements AuthRepository {
  User? signedIn;
  UserCredential? nextCredential;
  UserCredential? googleCredential;
  int deletes = 0;
  int signOuts = 0;
  Object? linkError;
  String? displayName;

  @override
  User? get currentUser => signedIn;

  Set<String> providers = {'password'};
  int verificationEmails = 0;
  User? afterReload;

  @override
  Set<String> get providerIds => providers;

  @override
  Future<void> sendEmailVerification() async => verificationEmails++;

  @override
  Future<User?> reloadUser() async => signedIn = afterReload ?? signedIn;

  @override
  Future<UserCredential> createAccount(String email, String password) async {
    final credential = FakeCredential(FakeUser('new-uid', email: email));
    signedIn = credential.user;
    return credential;
  }

  @override
  Future<UserCredential> signInWithCredential(AuthCredential credential) async {
    signedIn = nextCredential!.user;
    return nextCredential!;
  }

  @override
  Future<UserCredential?> signInWithGoogle() async => googleCredential;

  // Sign in with Apple.
  bool appleAvailable = true;
  UserCredential? appleCredential;
  Object? appleError;
  ({String? authorizationCode})? appleReauth;
  int appleReauths = 0;
  final revokedCodes = <String>[];
  final events = <String>[];

  @override
  bool get appleSignInAvailable => appleAvailable;

  @override
  Future<UserCredential?> signInWithApple() async {
    if (appleError != null) throw appleError!;
    final credential = appleCredential;
    if (credential != null) signedIn = credential.user;
    return credential;
  }

  @override
  Future<({String? authorizationCode})?> reauthenticateWithApple() async {
    appleReauths++;
    return appleReauth;
  }

  @override
  Future<void> revokeAppleToken(String authorizationCode) async {
    events.add('revoke');
    revokedCodes.add(authorizationCode);
  }

  @override
  Future<UserCredential> linkCredential(AuthCredential credential) async {
    if (linkError != null) throw linkError!;
    return FakeCredential(signedIn!);
  }

  @override
  Future<void> updateDisplayName(String name) async => displayName = name;

  @override
  Future<void> deleteCurrentUser() async {
    events.add('delete-user');
    deletes++;
  }

  final resetEmails = <String>[];

  @override
  Future<void> sendPasswordResetEmail(String email) async =>
      resetEmails.add(email);

  @override
  Future<void> signOut() async {
    signOuts++;
    signedIn = null;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeUserRepository implements UserRepository {
  final Map<String, UserModel> profiles = {};
  final List<UserModel> created = [];
  final List<Map<String, dynamic>> updates = [];

  @override
  Future<UserModel?> getUser(String uid) async => profiles[uid];

  @override
  Future<UserModel> createUser(UserModel user) async {
    final existing = profiles[user.id];
    if (existing != null) return existing;
    created.add(user);
    return profiles[user.id] = user;
  }

  @override
  Future<void> updateFields(String uid, Map<String, dynamic> fields) async {
    updates.add({'uid': uid, ...fields});
  }

  final deletedData = <String>[];

  @override
  Future<void> deleteUserData(String uid) async => deletedData.add(uid);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final phoneCredential = PhoneAuthProvider.credential(
  verificationId: 'v',
  smsCode: '123456',
);

void main() {
  late FakeAuthRepository auth;
  late FakeUserRepository users;
  late AuthService service;

  setUp(() {
    auth = FakeAuthRepository();
    users = FakeUserRepository();
    service = AuthService(auth, users);
  });

  group('register', () {
    test('creates the profile without a phone number', () async {
      final profile = await service.register(
        fullName: '  Rahim  ',
        email: 'rahim@example.com',
        password: 'password1',
      );
      expect(profile.id, 'new-uid');
      expect(profile.fullName, 'Rahim');
      expect(profile.phone, isNull);
      expect(auth.displayName, 'Rahim');
    });

    test('retrying with the same signed-in email reuses the account', () async {
      auth.signedIn = FakeUser('existing', email: 'Rahim@Example.com');
      users.profiles['existing'] = UserModel(
        id: 'existing',
        fullName: 'Rahim',
        email: 'rahim@example.com',
      );
      final profile = await service.register(
        fullName: 'Rahim',
        email: 'rahim@example.com',
        password: 'password1',
      );
      expect(profile.id, 'existing');
      expect(users.created, isEmpty);
      expect(auth.signOuts, 0);
    });

    test('a different signed-in account is signed out first', () async {
      auth.signedIn = FakeUser('other', email: 'other@example.com');
      final profile = await service.register(
        fullName: 'Rahim',
        email: 'rahim@example.com',
        password: 'password1',
      );
      expect(auth.signOuts, 1);
      expect(profile.id, 'new-uid');
    });
  });

  group('email verification', () {
    test('an unverified email/password account must verify', () {
      auth.signedIn = FakeUser('u1', email: 'a@example.com');
      expect(service.needsEmailVerification, isTrue);
    });

    test('verified or Google accounts go straight in', () {
      auth.signedIn = FakeUser('u1', email: 'a@b.c', emailVerified: true);
      expect(service.needsEmailVerification, isFalse);

      auth.signedIn = FakeUser('u2', email: 'g@gmail.com');
      auth.providers = {'google.com'};
      expect(service.needsEmailVerification, isFalse);

      auth.providers = {'password', 'google.com'};
      expect(service.needsEmailVerification, isFalse);
    });

    test('signed out needs nothing', () {
      expect(service.needsEmailVerification, isFalse);
    });

    test('checkEmailVerified reloads the account', () async {
      auth.signedIn = FakeUser('u1', email: 'a@b.c');
      expect(await service.checkEmailVerified(), isFalse);
      auth.afterReload = FakeUser('u1', email: 'a@b.c', emailVerified: true);
      expect(await service.checkEmailVerified(), isTrue);
    });

    test('sendEmailVerification asks Firebase to email the link', () async {
      auth.signedIn = FakeUser('u1', email: 'a@b.c');
      await service.sendEmailVerification();
      expect(auth.verificationEmails, 1);
    });
  });

  group('linkPhone', () {
    test('stores the phone only after the SMS credential links', () async {
      auth.signedIn = FakeUser('u1', email: 'a@example.com');
      await service.linkPhone(phoneCredential, '+8801700000000');
      expect(users.updates.single, {'uid': 'u1', 'phone': '+8801700000000'});
    });

    test('a number linked to another account is rejected', () async {
      auth.signedIn = FakeUser('u1', email: 'a@example.com');
      auth.linkError = FirebaseAuthException(code: 'credential-already-in-use');
      await expectLater(
        service.linkPhone(phoneCredential, '+8801700000000'),
        throwsA(isA<FirebaseAuthException>()),
      );
      expect(users.updates, isEmpty);
    });
  });

  group('phone sign-in', () {
    test('an unregistered number is removed again and rejected', () async {
      auth.nextCredential = FakeCredential(
        FakeUser('ghost', phoneNumber: '+8801800000000'),
        isNewUser: true,
      );
      await expectLater(
        service.signInWithPhone(phoneCredential),
        throwsA(isA<AppException>()),
      );
      expect(auth.deletes, 1);
      expect(auth.signOuts, 1);
      expect(users.created, isEmpty);
    });

    test('a registered number loads the existing profile', () async {
      users.profiles['u1'] = UserModel(
        id: 'u1',
        fullName: 'Karim',
        email: 'k@example.com',
        address: 'Mirpur, Dhaka',
        latitude: 23.82,
        longitude: 90.36,
      );
      auth.nextCredential = FakeCredential(FakeUser('u1'));
      final profile = await service.signInWithPhone(phoneCredential);
      expect(profile.address, 'Mirpur, Dhaka');
      expect(users.created, isEmpty);
    });
  });

  group('Google sign-in and missing profiles', () {
    test('cancelled Google dialog returns null', () async {
      expect(await service.signInWithGoogle(), isNull);
    });

    test('first Google sign-in creates a profile from the account', () async {
      auth.googleCredential = FakeCredential(
        FakeUser('g1', email: 'g@example.com', displayName: 'Gita'),
        isNewUser: true,
      );
      final profile = await service.signInWithGoogle();
      expect(profile?.fullName, 'Gita');
      expect(users.created.single.email, 'g@example.com');
    });

    test('an existing profile is never overwritten', () async {
      users.profiles['g1'] = UserModel(
        id: 'g1',
        fullName: 'Edited Name',
        email: 'g@example.com',
        churchAffiliation: 'GACC',
      );
      final profile = await service.ensureProfile(
        FakeUser('g1', email: 'g@example.com', displayName: 'Google Name'),
      );
      expect(profile.fullName, 'Edited Name');
      expect(profile.churchAffiliation, 'GACC');
      expect(users.created, isEmpty);
    });
  });

  group('Sign in with Apple', () {
    test('closing the Apple sheet returns null and creates nothing', () async {
      auth.appleCredential = null;
      expect(await service.signInWithApple(), isNull);
      expect(users.created, isEmpty);
    });

    test(
      'first sign-in with a hidden email and a name creates one profile',
      () async {
        auth.appleCredential = FakeCredential(
          FakeUser(
            'apple-1',
            email: 'x7k2p9@privaterelay.appleid.com',
            displayName: 'Ana Pérez',
            emailVerified: true,
          ),
          isNewUser: true,
        );
        final profile = (await service.signInWithApple())!;
        expect(profile.id, 'apple-1');
        expect(profile.email, 'x7k2p9@privaterelay.appleid.com');
        expect(profile.fullName, 'Ana Pérez');
        expect(users.created.length, 1);
      },
    );

    test(
      'no name and no email from Apple still gives a usable profile',
      () async {
        auth.appleCredential = FakeCredential(FakeUser('apple-2'));
        final profile = (await service.signInWithApple())!;
        expect(profile.fullName, '');
        expect(profile.email, '');
        expect(users.created.single.id, 'apple-2');
      },
    );

    test(
      'a returning user keeps the existing profile (no duplicate)',
      () async {
        users.profiles['apple-3'] = UserModel(
          id: 'apple-3',
          fullName: 'Ana',
          email: 'x@privaterelay.appleid.com',
          address: 'Demra',
        );
        // Apple sends no name on later sign-ins.
        auth.appleCredential = FakeCredential(FakeUser('apple-3'));
        final profile = (await service.signInWithApple())!;
        expect(profile.fullName, 'Ana');
        expect(profile.address, 'Demra');
        expect(users.created, isEmpty);
        expect(users.updates, isEmpty);
      },
    );

    test('a nameless profile takes the name when Apple provides it', () async {
      users.profiles['apple-4'] = UserModel(
        id: 'apple-4',
        fullName: '',
        email: 'a@example.com',
      );
      auth.appleCredential = FakeCredential(
        FakeUser('apple-4', displayName: ' Ana '),
      );
      final profile = (await service.signInWithApple())!;
      expect(profile.fullName, 'Ana');
      expect(users.updates.single, {'uid': 'apple-4', 'fullName': 'Ana'});
      expect(users.created, isEmpty);
    });

    test('errors reach the caller', () async {
      auth.appleError = FirebaseAuthException(
        code: 'account-exists-with-different-credential',
      );
      expect(service.signInWithApple(), throwsA(isA<FirebaseAuthException>()));
    });

    test('Apple accounts never need email verification', () {
      auth.signedIn = FakeUser('apple-5', email: 'a@example.com');
      auth.providers = {'apple.com'};
      expect(service.needsEmailVerification, isFalse);
    });

    test(
      'deleting an Apple account confirms with Apple and revokes tokens',
      () async {
        auth.signedIn = FakeUser('apple-6', email: 'a@example.com');
        auth.providers = {'apple.com'};
        auth.appleReauth = (authorizationCode: 'code-123');
        expect(service.deletionConfirmationProvider, 'apple.com');

        expect(await service.reauthenticateForDeletion(), isTrue);
        await service.deleteAccount();

        expect(auth.appleReauths, 1);
        expect(auth.revokedCodes, ['code-123']);
        expect(users.deletedData, ['apple-6']);
        // Revoked while still signed in, before the account is deleted.
        expect(auth.events, ['revoke', 'delete-user']);
      },
    );

    test('cancelling the Apple confirmation deletes nothing', () async {
      auth.signedIn = FakeUser('apple-7', email: 'a@example.com');
      auth.providers = {'apple.com'};
      auth.appleReauth = null;
      expect(await service.reauthenticateForDeletion(), isFalse);
      expect(users.deletedData, isEmpty);
      expect(auth.deletes, 0);
    });
  });

  test('a password reset email goes to the given address', () async {
    await service.sendPasswordResetEmail('a@example.com');
    expect(auth.resetEmails, ['a@example.com']);
  });
}
