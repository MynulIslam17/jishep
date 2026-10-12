class PrayerCycleModel {
  final int completed;
  final int target;
  final int todayPrayed;
  final int todayTotal;

  PrayerCycleModel({
    required this.completed,
    required this.target,
    required this.todayPrayed,
    required this.todayTotal,
  });

  factory PrayerCycleModel.fromJson(Map<String, dynamic> json) {
    return PrayerCycleModel(
      completed: json['completed'] is int ? json['completed'] : 12,
      target: json['target'] is int ? json['target'] : 20,
      todayPrayed: json['todayPrayed'] is int ? json['todayPrayed'] : 3,
      todayTotal: json['todayTotal'] is int ? json['todayTotal'] : 5,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'completed': completed,
      'target': target,
      'todayPrayed': todayPrayed,
      'todayTotal': todayTotal,
    };
  }
}
