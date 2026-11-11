/// Facts used in the Terms of Use, Privacy Policy and public website, in one
/// place. After changing anything here run
/// `dart run tool/build_legal_pages.dart` so the web pages match the app.
///
/// Deliberately absent until the client confirms them: a mailing address
/// and a governing-law / court jurisdiction (see docs/store_privacy.md).
abstract final class LegalInfo {
  static const String appName = 'GPS Para El Cielo';

  /// From the gaccchurch.org page header ("Global Alliance of Christian
  /// Churches, inc"). Confirm the exact registered name with the client.
  static const String operatorName =
      'Global Alliance of Christian Churches, Inc.';
  static const String operatorShortName = 'GACC';
  static const String operatorWebsite = 'https://gaccchurch.org';

  /// Support, privacy and legal contact (given by the client).
  static const String contactEmail = 'office@gaccchurch.org';

  static const String effectiveDate = 'November 11, 2026';

  static const int minimumAge = 13;

  /// Public website (Firebase Hosting on gps-cielo; see `legal_site/`).
  static const String siteUrl = 'https://gps-cielo.web.app';
  static const String privacyUrl = '$siteUrl/privacy';
  static const String termsUrl = '$siteUrl/terms';
  static const String supportUrl = '$siteUrl/support';
  static const String deleteAccountUrl = '$siteUrl/delete-account';
}
