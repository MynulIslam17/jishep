import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:gps_cielo/features/onboarding/data/models/onboarding_slide_model.dart';
import 'package:gps_cielo/features/onboarding/domain/services/onboarding_service.dart';
import 'package:gps_cielo/routes/app_routes.dart';

class OnboardingController extends GetxController {
  final OnboardingService _service;

  OnboardingController(this._service);

  final PageController pageController = PageController();
  final currentPage = 0.obs;
  final slides = <OnboardingSlideModel>[].obs;

  @override
  void onInit() {
    super.onInit();
    slides.assignAll(_service.getOnboardingSlides());
  }

  void onPageChanged(int index) {
    currentPage.value = index;
  }

  void skip() {
    Get.offAllNamed(AppRoutes.signIn);
  }

  void getStarted() {
    Get.offAllNamed(AppRoutes.signIn);
  }

  @override
  void onClose() {
    pageController.dispose();
    super.onClose();
  }
}
