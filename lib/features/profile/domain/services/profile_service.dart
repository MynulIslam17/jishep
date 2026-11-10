import 'dart:convert';

import 'package:get/get.dart';
import 'package:gps_cielo/core/data/user_repository.dart';
import 'package:gps_cielo/core/models/user_model.dart';
import 'package:gps_cielo/core/services/home_address_service.dart';
import 'package:gps_cielo/core/services/household_store.dart';
import 'package:gps_cielo/core/services/location_service.dart';
import 'package:gps_cielo/core/utils/firebase_error_mapper.dart';
import 'package:gps_cielo/features/auth/data/repositories/auth_repository.dart';

class ProfileService {
  final UserRepository _userRepository;
  final AuthRepository _authRepository;
  final HouseholdStore _store;
  final LocationService _locationService;
  final HomeAddressService _homeAddress;

  ProfileService(
    this._userRepository,
    this._authRepository,
    this._store,
    this._locationService,
    this._homeAddress,
  );

  RxInt get homesPrayed => _store.prayedCount;

  RxInt get visitsMade => _store.visitedCount;

  Future<UserModel> updateAddress(
    UserModel user,
    String address, {
    ResolvedLocation? location,
  }) async {
    location ??= await _locationService.resolveAddress(address);
    return _homeAddress.save(user, location);
  }

  /// One-shot GPS reading for the address form. Nothing is saved.
  Future<ResolvedLocation> currentLocation() =>
      _locationService.currentLocation();

  /// Saves the daily target, the default number of households and the
  /// search range in km.
  Future<void> updatePrayerPreferences(
    String uid, {
    required int dailyTarget,
    required int radiusHomes,
    required double searchRadiusKm,
  }) {
    return _userRepository.updateFields(uid, {
      'dailyPrayerTarget': dailyTarget,
      'radiusHomes': radiusHomes,
      'searchRadiusKm': searchRadiusKm,
    });
  }

  /// Saves name and church. The email is the sign-in identity and is not
  /// editable from the profile.
  Future<void> updateProfileInfo({
    required UserModel user,
    required String fullName,
    required String churchAffiliation,
  }) async {
    await _userRepository.updateFields(user.id, {
      'fullName': fullName,
      'churchAffiliation': churchAffiliation,
    });
    await _authRepository.updateDisplayName(fullName);
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
