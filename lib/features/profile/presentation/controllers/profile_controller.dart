import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:gps_cielo/core/models/user_model.dart';
import 'package:gps_cielo/core/services/location_service.dart';
import 'package:gps_cielo/core/utils/firebase_error_mapper.dart';
import 'package:gps_cielo/core/utils/show_snackbar.dart';
import 'package:gps_cielo/core/utils/validators.dart';
import 'package:gps_cielo/features/auth/data/repositories/auth_repository.dart';
import 'package:gps_cielo/features/auth/domain/services/auth_service.dart';
import 'package:gps_cielo/features/auth/presentation/controllers/auth_controller.dart';
import 'package:gps_cielo/routes/app_routes.dart';
import 'package:gps_cielo/features/profile/domain/services/profile_service.dart';
import 'package:image_picker/image_picker.dart';
import 'package:gps_cielo/core/utils/search_range.dart';

class ProfileController extends GetxController {
  final ProfileService _service;
  final AuthController _authController;

  ProfileController(this._service, this._authController);

  final user = Rxn<UserModel>();
  final isLoading = false.obs;
  final isUploadingAvatar = false.obs;

  /// Phone being added in Edit Profile (E.164) and its SMS send state.
  final pendingPhone = ''.obs;
  final phoneController = TextEditingController();
  final isSendingPhoneCode = false.obs;
  final selectedPrayerTarget = 5.obs;

  final List<Worker> _workers = [];

  @override
  void onInit() {
    super.onInit();
    loadProfile();
    _workers.addAll([
      ever(_authController.currentUser, (_) => loadProfile()),
      ever(_service.homesPrayed, (_) => loadProfile()),
      ever(_service.visitsMade, (_) => loadProfile()),
    ]);
  }

  /// Combines the live Firestore profile with the household stats.
  void loadProfile() {
    final current = _authController.currentUser.value;
    if (current == null) {
      user.value = null;
      return;
    }
    user.value = current.copyWith(
      homesPrayed: _service.homesPrayed.value,
      visitsMade: _service.visitsMade.value,
    );
    selectedPrayerTarget.value = current.dailyPrayerTarget;
  }

  Future<void> updateAddress(
    String newAddress, {
    ResolvedLocation? location,
  }) async {
    final current = _authController.currentUser.value;
    if (newAddress.trim().isEmpty || current == null) return;

    isLoading.value = true;
    try {
      final updated = await _service.updateAddress(
        current,
        newAddress.trim(),
        location: location,
      );
      _authController.updateUser(updated);
      SnackbarService.showSuccess(
        'Address Updated',
        'Your location has been saved.',
      );
    } catch (error) {
      SnackbarService.showError(
        'Address Not Saved',
        FirebaseErrorMapper.message(error),
      );
    } finally {
      isLoading.value = false;
    }
  }

  /// Reads the device GPS for the address form. Returns null on failure
  /// (after telling the user why). Nothing is saved here.
  Future<ResolvedLocation?> locateDevice() async {
    try {
      return await _service.currentLocation();
    } catch (error) {
      SnackbarService.showError(
        'Location Unavailable',
        FirebaseErrorMapper.message(error),
      );
      return null;
    }
  }

  Future<void> updatePrayerPreferences(
    int target,
    int radiusHomes,
    double rangeKm,
  ) async {
    final current = _authController.currentUser.value;
    if (current == null) return;
    if (target == current.dailyPrayerTarget &&
        radiusHomes == current.radiusHomes &&
        rangeKm == current.searchRadiusKm) {
      return;
    }

    selectedPrayerTarget.value = target;
    isLoading.value = true;
    try {
      _authController.updateUser(
        current.copyWith(
          dailyPrayerTarget: target,
          radiusHomes: radiusHomes,
          searchRadiusKm: rangeKm,
        ),
      );
      await _service.updatePrayerPreferences(
        current.id,
        dailyTarget: target,
        radiusHomes: radiusHomes,
        searchRadiusKm: rangeKm,
      );
      SnackbarService.showSuccess(
        'Preferences Saved',
        '$target households/day · $radiusHomes homes within '
            '${SearchRange.formatKm(rangeKm)}.',
      );
    } catch (error) {
      _authController.updateUser(current);
      SnackbarService.showError(
        'Preferences Not Saved',
        FirebaseErrorMapper.message(error),
      );
    } finally {
      isLoading.value = false;
    }
  }

  Future<bool> updateProfileInfo({
    required String fullName,
    required String churchAffiliation,
  }) async {
    final current = _authController.currentUser.value;
    if (current == null) return false;

    final validationError = AppValidator.name(fullName);
    if (validationError != null) {
      SnackbarService.showError('Validation Error', validationError);
      return false;
    }

    isLoading.value = true;
    try {
      await _service.updateProfileInfo(
        user: current,
        fullName: fullName.trim(),
        churchAffiliation: churchAffiliation.trim(),
      );
      _authController.updateUser(
        current.copyWith(
          fullName: fullName.trim(),
          churchAffiliation: churchAffiliation.trim(),
        ),
      );

      SnackbarService.showSuccess(
        'Profile Updated',
        'Changes saved successfully.',
      );
      return true;
    } catch (error) {
      SnackbarService.showError(
        'Profile Not Saved',
        FirebaseErrorMapper.message(error),
      );
      return false;
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> pickAndUploadAvatar() async {
    final current = _authController.currentUser.value;
    if (current == null || isUploadingAvatar.value) return;

    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 256,
      maxHeight: 256,
      imageQuality: 70,
    );
    if (picked == null) return;

    isUploadingAvatar.value = true;
    try {
      final encoded = await _service.saveAvatar(
        current.id,
        await picked.readAsBytes(),
      );
      _authController.updateUser(current.copyWith(avatarBase64: encoded));
      SnackbarService.showSuccess(
        'Photo Updated',
        'Your profile photo has been saved.',
      );
    } catch (error) {
      SnackbarService.showError(
        'Upload Failed',
        FirebaseErrorMapper.message(error),
      );
    } finally {
      isUploadingAvatar.value = false;
    }
  }

  Future<void> sendSupportMessage(String message) async {
    final current = _authController.currentUser.value;
    if (message.trim().isEmpty || current == null) return;

    try {
      await _service.sendSupportMessage(current, message.trim());
      SnackbarService.showSuccess(
        'Message Sent',
        'Support team will contact you shortly.',
      );
    } catch (error) {
      SnackbarService.showError(
        'Message Not Sent',
        FirebaseErrorMapper.message(error),
      );
    }
  }

  /// Sends an SMS code to [pendingPhone] and opens the code screen. Once
  /// verified, the number is linked to the account for phone sign-in.
  Future<void> verifyPendingPhone(String typedNumber) async {
    if (isSendingPhoneCode.value) return;
    final phone = pendingPhone.value.trim();
    final error = AppValidator.phone(typedNumber);
    if (error != null || phone.isEmpty) {
      SnackbarService.showError(
        'Phone Number',
        error ?? 'Please enter your phone number',
      );
      return;
    }

    isSendingPhoneCode.value = true;
    try {
      final result = await _authController.sendPhoneCode(phone);
      switch (result) {
        case SmsCodeSent(:final verificationId, :final resendToken):
          Get.toNamed(
            AppRoutes.otpVerification,
            arguments: {
              'phone': phone,
              'purpose': OtpPurpose.addPhone,
              'verificationId': verificationId,
              'resendToken': resendToken,
            },
          );
        case SmsAutoVerified(:final credential):
          await _authController.completePhoneVerification(
            purpose: OtpPurpose.addPhone,
            credential: credential,
            phone: phone,
          );
      }
    } catch (error) {
      SnackbarService.showError(
        'Code Not Sent',
        FirebaseErrorMapper.message(error),
      );
    } finally {
      isSendingPhoneCode.value = false;
    }
  }

  Future<void> signOut() => _authController.signOut();

  bool get accountUsesPassword => _authController.accountUsesPassword;

  String? get deletionConfirmationLabel =>
      _authController.deletionConfirmationLabel;

  /// Returns true when the account was deleted.
  Future<bool> deleteAccount({String? password}) async {
    try {
      final deleted = await _authController.deleteAccount(password: password);
      if (deleted) {
        SnackbarService.showSuccess(
          'Account Deleted',
          'Your account and data have been permanently deleted.',
        );
      }
      return deleted;
    } catch (error) {
      SnackbarService.showError(
        'Could Not Delete Account',
        FirebaseErrorMapper.message(error),
      );
      return false;
    }
  }

  @override
  void onClose() {
    for (final worker in _workers) {
      worker.dispose();
    }
    phoneController.dispose();
    super.onClose();
  }
}
