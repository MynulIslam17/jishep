abstract final class AppStrings {
  static const String appName = 'GPS PARA EL CIELO';

  /// No household data exists for an area (Overture cells not loaded).
  static const String areaUnavailable = "This area isn't available yet";
  static const String areaComingSoon = "We're adding more states soon.";

  /// States whose households are loaded (keep in step with the seeding).
  static const String areasAvailable = 'Available now: New Jersey, California';
  static const String appTagline = 'Conectando hogares, alcanzando vidas.';

  // Primary location (chosen once at signup; blueprint §2.1).
  static const String primaryNeighborhood = 'Your neighborhood';
  static const String primaryLocationFixed =
      'Your neighborhood was set when you joined, so your prayer list stays '
      'with the homes around you.';
  static const String primaryLocationHelp =
      'Moved, or chose the wrong address? Contact support and we will '
      'update it for you.';
  static const String primaryLocationSetupNote =
      'Choose carefully: this becomes your neighborhood. To change it later, '
      'contact support.';
  static const String contactSupport = 'Contact support';
  static const String locationCorrectionMessage =
      'Please update my neighborhood address. My correct address is: ';

  // Auth Strings
  static const String welcomeBack = 'Welcome back';
  static const String signInToAccount = 'Sign in to your account';
  static const String emailAddress = 'Email address';
  static const String emailHint = 'you@example.com';
  static const String password = 'Password';
  static const String passwordHint = 'Your password';
  static const String forgotPassword = 'Forgot your password?';
  static const String signIn = 'Sign in';
  static const String orContinueWith = 'or continue with';
  static const String continueWithGoogle = 'Continue with Google';
  static const String dontHaveAccount = "Don't have an account? ";
  static const String signUp = 'Sign up';
  static const String createAccount = 'Create account';
  static const String joinGpsCielo = 'Join GPS Para el Cielo';
  static const String fullName = 'Full name';
  static const String nameHint = 'e.g. María González';
  static const String phoneNumber = 'Phone number';
  static const String phoneHint = '+1 (201) 555-0000';
  static const String passwordMinLength = 'Minimum 8 characters';
  static const String agreeToTerms =
      'I agree to the Terms of Use and Privacy Policy';
  static const String alreadyHaveAccount = 'Already have an account? ';

  // Navigation
  static const String navHome = 'Home';
  static const String navNeighborhood = 'Neighborhood';
  static const String navPrayerList = 'Prayer List';
  static const String navFollowUp = 'Follow-up';
  static const String navProfile = 'Profile';

  // Home
  static const String pray = 'Pray';
  static const String prayed = 'Prayed';
  static const String visited = 'Visited';
  static const String followUpAction = 'Follow up';
}
