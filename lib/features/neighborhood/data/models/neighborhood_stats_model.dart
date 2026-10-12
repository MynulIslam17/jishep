class NeighborhoodStatsModel {
  final int totalHouseholds;
  final int radiusHomes;
  final double zoomLevel;

  NeighborhoodStatsModel({
    required this.totalHouseholds,
    required this.radiusHomes,
    this.zoomLevel = 1.0,
  });

  factory NeighborhoodStatsModel.fromJson(Map<String, dynamic> json) {
    return NeighborhoodStatsModel(
      totalHouseholds: json['totalHouseholds'] is int ? json['totalHouseholds'] : 24,
      radiusHomes: json['radiusHomes'] is int ? json['radiusHomes'] : 10,
      zoomLevel: json['zoomLevel'] is num ? (json['zoomLevel'] as num).toDouble() : 1.0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'totalHouseholds': totalHouseholds,
      'radiusHomes': radiusHomes,
      'zoomLevel': zoomLevel,
    };
  }
}
