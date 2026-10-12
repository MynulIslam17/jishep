class SplashModel {
  final String appName;
  final String welcomeText;
  final Duration displayDuration;

  const SplashModel({
    this.appName = 'GPS PARA EL CIELO',
    this.welcomeText = 'WELCOME',
    this.displayDuration = const Duration(seconds: 2, milliseconds: 500),
  });
}
