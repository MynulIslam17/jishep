class OnboardingSlideModel {
  final int index;
  final String? tag;
  final String? title;
  final String? quote;
  final String? scriptureRef;
  final String? description;
  final String? imageAsset;
  final bool showGetStarted;

  const OnboardingSlideModel({
    required this.index,
    this.tag,
    this.title,
    this.quote,
    this.scriptureRef,
    this.description,
    this.imageAsset,
    this.showGetStarted = false,
  });
}
