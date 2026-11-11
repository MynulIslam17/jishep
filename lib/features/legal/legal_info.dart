/// Facts used in the Terms of Use and Privacy Policy, in one place.
///
/// Values marked PLACEHOLDER were not on gaccchurch.org (checked
/// 2026-11-11). Replace them, then run `dart run tool/build_legal_pages.dart`
/// so the web pages match the app.
abstract final class LegalInfo {
  static const String appName = 'GPS Para El Cielo';

  /// From the gaccchurch.org page header.
  static const String operatorName =
      'Global Alliance of Christian Churches, Inc.';
  static const String operatorShortName = 'GACC';
  static const String operatorWebsite = 'https://gaccchurch.org';

  /// The support address the app already shows.
  static const String contactEmail = 'support@gpscielochurch.org';

  /// PLACEHOLDER: the organization's mailing address.
  static const String mailingAddress =
      '1200 Main Street, Suite 400, Houston, TX 77002, United States';

  /// PLACEHOLDER: the US state whose law governs the Terms.
  static const String governingState = 'Texas';

  /// PLACEHOLDER: county for the courts named in the Terms.
  static const String venueCounty = 'Harris County';

  static const String effectiveDate = 'November 11, 2026';

  static const int minimumAge = 13;

  /// Public copies (required by App Store Connect and Google Play).
  /// Firebase Hosting on gps-cielo; see `legal_site/`.
  static const String privacyUrl = 'https://gps-cielo.web.app/privacy';
  static const String termsUrl = 'https://gps-cielo.web.app/terms';
}
