class ProfileStatsModel {
  final int homesPrayed;
  final int visitsMade;
  final int dailyPrayerTarget;

  ProfileStatsModel({
    required this.homesPrayed,
    required this.visitsMade,
    required this.dailyPrayerTarget,
  });

  factory ProfileStatsModel.fromJson(Map<String, dynamic> json) {
    return ProfileStatsModel(
      homesPrayed: json['homesPrayed'] is int ? json['homesPrayed'] : 47,
      visitsMade: json['visitsMade'] is int ? json['visitsMade'] : 12,
      dailyPrayerTarget: json['dailyPrayerTarget'] is int
          ? json['dailyPrayerTarget']
          : 5,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'homesPrayed': homesPrayed,
      'visitsMade': visitsMade,
      'dailyPrayerTarget': dailyPrayerTarget,
    };
  }
}
