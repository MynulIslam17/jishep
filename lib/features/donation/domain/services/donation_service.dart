import 'dart:convert';

import 'package:gps_cielo/core/config/app_config.dart';
import 'package:http/http.dart' as http;

enum DonationFrequency { oneTime, monthly }

class DonationNotConfiguredException implements Exception {
  const DonationNotConfiguredException();
}

/// Builds the Stripe-hosted page the donor is sent to.
class DonationService {
  DonationService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const List<int> presetAmounts = [5, 10, 25, 50, 100, 250];
  static const int minAmount = 1;
  static const int maxAmount = 10000;

  bool get isConfigured =>
      AppConfig.donationCheckoutEndpoint.isNotEmpty ||
      AppConfig.donationOneTimeLink.isNotEmpty ||
      AppConfig.donationMonthlyLink.isNotEmpty;

  Future<Uri> checkoutUri({
    required int amount,
    required DonationFrequency frequency,
    String? uid,
    String? email,
  }) async {
    final monthly = frequency == DonationFrequency.monthly;

    // Preferred: a backend creates a Checkout Session for the exact amount.
    if (AppConfig.donationCheckoutEndpoint.isNotEmpty) {
      final response = await _client
          .post(
            Uri.parse(AppConfig.donationCheckoutEndpoint),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'amount': amount * 100,
              'currency': AppConfig.donationCurrency,
              'recurring': monthly,
              'uid': uid,
              'email': email,
            }),
          )
          .timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) {
        throw Exception('Checkout failed (${response.statusCode})');
      }
      final url = (jsonDecode(response.body) as Map<String, dynamic>)['url'];
      return Uri.parse(url as String);
    }

    // Fallback: a Stripe Payment Link (donor confirms the amount on Stripe).
    final link = monthly
        ? AppConfig.donationMonthlyLink
        : AppConfig.donationOneTimeLink;
    if (link.isEmpty) throw const DonationNotConfiguredException();

    final base = Uri.parse(link);
    return base.replace(
      queryParameters: {
        ...base.queryParameters,
        if (uid != null && uid.isNotEmpty) 'client_reference_id': uid,
        if (email != null && email.isNotEmpty) 'prefilled_email': email,
      },
    );
  }
}
