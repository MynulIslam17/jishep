import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:gps_cielo/core/utils/show_snackbar.dart';
import 'package:gps_cielo/features/auth/presentation/controllers/auth_controller.dart';
import 'package:gps_cielo/features/donation/domain/services/donation_service.dart';
import 'package:url_launcher/url_launcher.dart';

class DonationController extends GetxController {
  DonationController(this._service, this._authController);

  final DonationService _service;
  final AuthController _authController;

  final frequency = DonationFrequency.oneTime.obs;
  final selectedPreset = RxnInt(25);
  final customAmount = RxnInt();
  final isLoading = false.obs;

  final customController = TextEditingController();
  final customFocus = FocusNode();

  List<int> get presets => DonationService.presetAmounts;

  int? get amount => customAmount.value ?? selectedPreset.value;

  bool get isAmountValid {
    final a = amount;
    return a != null &&
        a >= DonationService.minAmount &&
        a <= DonationService.maxAmount;
  }

  void setFrequency(int index) =>
      frequency.value = DonationFrequency.values[index];

  void selectPreset(int value) {
    selectedPreset.value = value;
    customAmount.value = null;
    customController.clear();
    customFocus.unfocus();
  }

  void onCustomChanged(String text) {
    final value = int.tryParse(text);
    customAmount.value = value;
    if (value != null) selectedPreset.value = null;
  }

  Future<void> donate() async {
    if (!isAmountValid) {
      SnackbarService.showError(
        'Check the amount',
        'Enter between \$${DonationService.minAmount} and '
            '\$${DonationService.maxAmount}.',
      );
      return;
    }
    if (!_service.isConfigured) {
      SnackbarService.showInfo(
        'Coming soon',
        'Online giving is being set up. Thank you for your heart to give!',
      );
      return;
    }

    isLoading.value = true;
    try {
      final user = _authController.currentUser.value;
      final uri = await _service.checkoutUri(
        amount: amount!,
        frequency: frequency.value,
        uid: user?.id,
        email: user?.email,
      );
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened) throw Exception('Could not open browser');
    } on DonationNotConfiguredException {
      SnackbarService.showInfo(
        'Coming soon',
        'Monthly giving is being set up. Try a one-time gift for now.',
      );
    } catch (_) {
      SnackbarService.showError(
        'Could not open checkout',
        'Please check your connection and try again.',
      );
    } finally {
      isLoading.value = false;
    }
  }

  @override
  void onClose() {
    customController.dispose();
    customFocus.dispose();
    super.onClose();
  }
}
