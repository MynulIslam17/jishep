class AppConfig {
  AppConfig._();

  static const String environment = 'development';
  static const bool isProduction = false;
  static const String appVersion = '1.0.0';
  static const int buildNumber = 1;

  // --- Donations (Stripe) ---
  // Gifts are paid on a Stripe-hosted page in the browser, never inside the
  // app, so no card data touches the app and no in-app purchase is involved.
  //
  // Preferred: an HTTPS endpoint (e.g. a Firebase Cloud Function) that takes
  // `{amount, currency, recurring, uid, email}` (amount in cents) and returns
  // `{url}` of a Stripe Checkout Session, so the amount picked in the app
  // carries over.
  static const String donationCheckoutEndpoint = '';

  // Fallback until that endpoint exists: Stripe Payment Links made in the
  // Stripe dashboard ("Customers choose what to pay"). The donor confirms the
  // amount again on Stripe's page.
  static const String donationOneTimeLink = '';
  static const String donationMonthlyLink = '';

  static const String donationCurrency = 'usd';
}
