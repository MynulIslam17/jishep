import 'package:gps_cielo/features/onboarding/data/models/onboarding_slide_model.dart';
import 'package:gps_cielo/features/onboarding/data/repositories/onboarding_repository.dart';

class OnboardingService {
  final OnboardingRepository _repository;

  OnboardingService(this._repository);

  List<OnboardingSlideModel> getOnboardingSlides() {
    return _repository.getSlides();
  }
}
