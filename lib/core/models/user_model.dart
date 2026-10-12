import 'package:cloud_firestore/cloud_firestore.dart';

class UserModel {
  final String id;
  final String fullName;
  final String email;
  final String? phone;
  final String? avatarUrl;

  /// Small JPEG profile photo stored directly in Firestore (base64).
  final String? avatarBase64;
  final String address;
  final String churchAffiliation;
  final int homesPrayed;
  final int visitsMade;
  final int dailyPrayerTarget;
  final int prayerCycleTarget;
  final int radiusHomes;
  final double? latitude;
  final double? longitude;

  UserModel({
    required this.id,
    required this.fullName,
    required this.email,
    this.phone,
    this.avatarUrl,
    this.avatarBase64,
    this.address = '',
    this.churchAffiliation = '',
    this.homesPrayed = 0,
    this.visitsMade = 0,
    this.dailyPrayerTarget = 5,
    this.prayerCycleTarget = 20,
    this.radiusHomes = 10,
    this.latitude,
    this.longitude,
  });

  /// True once the user has confirmed a home location.
  bool get hasLocation => latitude != null && longitude != null;

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id']?.toString() ?? '',
      fullName: json['fullName']?.toString() ?? json['name']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      phone: json['phone']?.toString(),
      avatarUrl: json['avatarUrl']?.toString(),
      avatarBase64: json['avatarBase64']?.toString(),
      address: json['address']?.toString() ?? '',
      churchAffiliation: json['churchAffiliation']?.toString() ?? '',
      homesPrayed: (json['homesPrayed'] as num?)?.toInt() ?? 0,
      visitsMade: (json['visitsMade'] as num?)?.toInt() ?? 0,
      dailyPrayerTarget: (json['dailyPrayerTarget'] as num?)?.toInt() ?? 5,
      prayerCycleTarget: (json['prayerCycleTarget'] as num?)?.toInt() ?? 20,
      radiusHomes: (json['radiusHomes'] as num?)?.toInt() ?? 10,
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
    );
  }

  factory UserModel.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    return UserModel.fromJson({...?doc.data(), 'id': doc.id});
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'fullName': fullName,
      'email': email,
      'phone': phone,
      'avatarUrl': avatarUrl,
      'avatarBase64': avatarBase64,
      'address': address,
      'churchAffiliation': churchAffiliation,
      'homesPrayed': homesPrayed,
      'visitsMade': visitsMade,
      'dailyPrayerTarget': dailyPrayerTarget,
      'prayerCycleTarget': prayerCycleTarget,
      'radiusHomes': radiusHomes,
      'latitude': latitude,
      'longitude': longitude,
    };
  }

  /// Fields stored on `users/{uid}`. Stats are derived from household status
  /// documents, so they are not persisted here.
  Map<String, dynamic> toFirestore() {
    return {
      'fullName': fullName,
      'email': email,
      'phone': phone,
      'avatarUrl': avatarUrl,
      'avatarBase64': avatarBase64,
      'address': address,
      'churchAffiliation': churchAffiliation,
      'dailyPrayerTarget': dailyPrayerTarget,
      'prayerCycleTarget': prayerCycleTarget,
      'radiusHomes': radiusHomes,
      'latitude': latitude,
      'longitude': longitude,
    };
  }

  UserModel copyWith({
    String? id,
    String? fullName,
    String? email,
    String? phone,
    String? avatarUrl,
    String? avatarBase64,
    String? address,
    String? churchAffiliation,
    int? homesPrayed,
    int? visitsMade,
    int? dailyPrayerTarget,
    int? prayerCycleTarget,
    int? radiusHomes,
    double? latitude,
    double? longitude,
  }) {
    return UserModel(
      id: id ?? this.id,
      fullName: fullName ?? this.fullName,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      avatarBase64: avatarBase64 ?? this.avatarBase64,
      address: address ?? this.address,
      churchAffiliation: churchAffiliation ?? this.churchAffiliation,
      homesPrayed: homesPrayed ?? this.homesPrayed,
      visitsMade: visitsMade ?? this.visitsMade,
      dailyPrayerTarget: dailyPrayerTarget ?? this.dailyPrayerTarget,
      prayerCycleTarget: prayerCycleTarget ?? this.prayerCycleTarget,
      radiusHomes: radiusHomes ?? this.radiusHomes,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
    );
  }
}
