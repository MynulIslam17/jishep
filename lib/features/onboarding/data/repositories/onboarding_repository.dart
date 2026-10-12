import 'package:gps_cielo/features/onboarding/data/models/onboarding_slide_model.dart';

class OnboardingRepository {
  List<OnboardingSlideModel> getSlides() {
    return const [
      OnboardingSlideModel(
        index: 0,
        tag: 'PRAY WITHOUT CEASING',
        title: 'Transform Your City Through Prayer',
        description:
            'Discover households in your neighborhood, pray for every family by name, and track God\'s movement.',
      ),
      OnboardingSlideModel(
        index: 1,
        tag: 'CONNECT WITH COMMUNITY',
        title: 'Systematic Outreach & Follow-up',
        description:
            'Keep notes, manage prayer requests, and build lasting bridges between neighbors and the church.',
      ),
      OnboardingSlideModel(
        index: 2,
        tag: 'WALK IN PURPOSE',
        title: 'Begin Your Outreach Journey',
        description:
            'Join hundreds of believers actively praying and sharing God\'s love in their neighborhoods.',
        showGetStarted: true,
      ),
    ];
  }
}
