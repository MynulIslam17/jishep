class HomeSummaryModel {
  final int target;
  final int completed;
  final int radiusHomes;
  final String scriptureVerse;
  final String scriptureReference;

  HomeSummaryModel({
    required this.target,
    required this.completed,
    required this.radiusHomes,
    required this.scriptureVerse,
    required this.scriptureReference,
  });

  factory HomeSummaryModel.fromJson(Map<String, dynamic> json) {
    return HomeSummaryModel(
      target: json['target'] is int ? json['target'] : 20,
      completed: json['completed'] is int ? json['completed'] : 12,
      radiusHomes: json['radiusHomes'] is int ? json['radiusHomes'] : 10,
      scriptureVerse:
          json['scriptureVerse']?.toString() ??
          '"Ask of me, and I will give you the nations as your inheritance."',
      scriptureReference: json['scriptureReference']?.toString() ?? 'Psalm 2:8',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'target': target,
      'completed': completed,
      'radiusHomes': radiusHomes,
      'scriptureVerse': scriptureVerse,
      'scriptureReference': scriptureReference,
    };
  }
}
