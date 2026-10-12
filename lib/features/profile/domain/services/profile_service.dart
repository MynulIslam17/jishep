import 'dart:convert';

import 'package:get/get.dart';
import 'package:gps_cielo/core/data/user_repository.dart';
import 'package:gps_cielo/core/models/user_model.dart';
import 'package:gps_cielo/core/services/household_store.dart';
import 'package:gps_cielo/core/services/location_service.dart';
import 'package:gps_cielo/core/utils/firebase_error_mapper.dart';
import 'package:gps_cielo/features/auth/data/repositories/auth_repository.dart';

class ProfileService {
  final UserRepository _userRepository;
  final AuthRepository _authRepository;
  final HouseholdStore _store;
  final LocationService _locationService;

  ProfileService(
    this._userRepository,
    this._authRepository,
    this._store,
    this._locationService,
  );

  RxInt get homesPrayed => _store.prayedCount;

  RxInt get visitsMade => _store.visitedCount;

  Future<UserModel> updateAddress(
    UserModel user,
    String address, {
    ResolvedLocation? location,
  }) async {
    location ??= await _locationService.resolveAddress(address);
    final updated = user.copyWith(
      address: location.address,
      latitude: location.latitude,
      longitude: location.longitude,
    );
    await _userRepository.updateLocation(
      uid: user.id,
      address: location.address,
      latitude: location.latitude,
      longitude: location.longitude,
    );
    await _store.bindUser(updated);
    return updated;
  }

  Future<void> updatePrayerPreferences(String uid, int dailyTarget) {
    return _userRepository.updateFields(uid, {
      'dailyPrayerTarget': dailyTarget,
    });
  }

  /// Saves name and church. A changed email is only applied after the user
  /// confirms it from the verification link; returns true when that link was
  /// sent.
  Future<bool> updateProfileInfo({
    required UserModel user,
    required String fullName,
    required String email,
    required String churchAffiliation,
  }) async {
    await _userRepository.updateFields(user.id, {
      'fullName': fullName,
      'churchAffiliation': churchAffiliation,
    });
    await _authRepository.updateDisplayName(fullName);

    final authEmail = _authRepository.currentUser?.email ?? user.email;
    if (email.toLowerCase() == authEmail.toLowerCase()) return false;

    await _authRepository.verifyBeforeUpdateEmail(email);
    return true;
  }

  /// Largest encoded photo accepted (Firestore documents are capped at 1 MiB).
  static const int maxAvatarBytes = 200 * 1024;

  /// Stores [jpegBytes] on the profile and returns the base64 string.
  Future<String> saveAvatar(String uid, List<int> jpegBytes) async {
    final encoded = base64Encode(jpegBytes);
    if (encoded.length > maxAvatarBytes) {
      throw const AppException(
        'That photo is too large. Please choose another.',
      );
    }
    await _userRepository.saveAvatar(uid, encoded);
    return encoded;
  }

  Future<void> sendSupportMessage(UserModel user, String message) {
    return _userRepository.sendSupportMessage(
      uid: user.id,
      email: user.email,
      message: message,
    );
  }
}
