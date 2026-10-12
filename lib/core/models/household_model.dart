import 'package:cloud_firestore/cloud_firestore.dart';

class HouseholdModel {
  final String id;
  final int number;
  final String residentName;
  final String address;
  final String cityStateZip;
  final bool isPrayed;
  final bool isVisited;
  final bool isInvited;
  final bool hasFollowUp;
  final String? followUpDate;
  final String? lastUpdated;
  final String? notes;
  final double latitude;
  final double longitude;
  final DateTime? prayedAt;
  final DateTime? updatedAt;

  HouseholdModel({
    required this.id,
    required this.number,
    required this.residentName,
    required this.address,
    this.cityStateZip = '',
    this.isPrayed = false,
    this.isVisited = false,
    this.isInvited = false,
    this.hasFollowUp = false,
    this.followUpDate,
    this.lastUpdated,
    this.notes,
    this.latitude = 0,
    this.longitude = 0,
    this.prayedAt,
    this.updatedAt,
  });

  String get fullAddress =>
      cityStateZip.isEmpty ? address : '$address, $cityStateZip';

  /// Builds a household from the shared `households/{id}` document merged with
  /// the signed-in user's `household_status/{id}` document (if any).
  factory HouseholdModel.fromFirestore({
    required DocumentSnapshot<Map<String, dynamic>> doc,
    Map<String, dynamic>? status,
    required int number,
  }) {
    final data = doc.data() ?? const <String, dynamic>{};
    final geo = data['geo'];
    final geopoint = geo is Map ? geo['geopoint'] : null;
    final updatedAt = _toDate(status?['updatedAt']);

    return HouseholdModel(
      id: doc.id,
      number: number,
      residentName: data['residentName']?.toString() ?? 'Resident',
      address: data['address']?.toString() ?? '',
      cityStateZip: data['cityStateZip']?.toString() ?? '',
      latitude: geopoint is GeoPoint ? geopoint.latitude : 0,
      longitude: geopoint is GeoPoint ? geopoint.longitude : 0,
      isPrayed: status?['isPrayed'] == true,
      isVisited: status?['isVisited'] == true,
      isInvited: status?['isInvited'] == true,
      hasFollowUp: status?['hasFollowUp'] == true,
      followUpDate: status?['followUpDate']?.toString(),
      notes: status?['notes']?.toString(),
      prayedAt: _toDate(status?['prayedAt']),
      updatedAt: updatedAt,
      lastUpdated: _describeUpdatedAt(updatedAt),
    );
  }

  factory HouseholdModel.fromJson(Map<String, dynamic> json) {
    return HouseholdModel(
      id: json['id']?.toString() ?? '',
      number: json['number'] is int
          ? json['number']
          : int.tryParse(json['number']?.toString() ?? '1') ?? 1,
      residentName: json['residentName']?.toString() ?? 'Resident',
      address: json['address']?.toString() ?? '',
      cityStateZip: json['cityStateZip']?.toString() ?? '',
      isPrayed: json['isPrayed'] == true,
      isVisited: json['isVisited'] == true,
      isInvited: json['isInvited'] == true,
      hasFollowUp: json['hasFollowUp'] == true,
      followUpDate: json['followUpDate']?.toString(),
      lastUpdated: json['lastUpdated']?.toString(),
      notes: json['notes']?.toString(),
      latitude: (json['latitude'] as num?)?.toDouble() ?? 0,
      longitude: (json['longitude'] as num?)?.toDouble() ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'number': number,
      'residentName': residentName,
      'address': address,
      'cityStateZip': cityStateZip,
      'isPrayed': isPrayed,
      'isVisited': isVisited,
      'isInvited': isInvited,
      'hasFollowUp': hasFollowUp,
      'followUpDate': followUpDate,
      'lastUpdated': lastUpdated,
      'notes': notes,
      'latitude': latitude,
      'longitude': longitude,
    };
  }

  /// The per-user fields written to `users/{uid}/household_status/{id}`.
  Map<String, dynamic> toStatusFirestore() {
    return {
      'isPrayed': isPrayed,
      'isVisited': isVisited,
      'isInvited': isInvited,
      'hasFollowUp': hasFollowUp,
      'followUpDate': hasFollowUp ? followUpDate : null,
      'notes': notes,
      'residentName': residentName,
      'address': fullAddress,
    };
  }

  bool hasSameStatusAs(HouseholdModel other) {
    return isPrayed == other.isPrayed &&
        isVisited == other.isVisited &&
        isInvited == other.isInvited &&
        hasFollowUp == other.hasFollowUp &&
        followUpDate == other.followUpDate &&
        notes == other.notes;
  }

  HouseholdModel copyWith({
    String? id,
    int? number,
    String? residentName,
    String? address,
    String? cityStateZip,
    bool? isPrayed,
    bool? isVisited,
    bool? isInvited,
    bool? hasFollowUp,
    String? followUpDate,
    String? lastUpdated,
    String? notes,
    double? latitude,
    double? longitude,
    DateTime? prayedAt,
    DateTime? updatedAt,
  }) {
    return HouseholdModel(
      id: id ?? this.id,
      number: number ?? this.number,
      residentName: residentName ?? this.residentName,
      address: address ?? this.address,
      cityStateZip: cityStateZip ?? this.cityStateZip,
      isPrayed: isPrayed ?? this.isPrayed,
      isVisited: isVisited ?? this.isVisited,
      isInvited: isInvited ?? this.isInvited,
      hasFollowUp: hasFollowUp ?? this.hasFollowUp,
      followUpDate: followUpDate ?? this.followUpDate,
      lastUpdated: lastUpdated ?? this.lastUpdated,
      notes: notes ?? this.notes,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      prayedAt: prayedAt ?? this.prayedAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  static DateTime? _toDate(Object? value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }

  static String? _describeUpdatedAt(DateTime? updatedAt) {
    if (updatedAt == null) return null;
    final diff = DateTime.now().difference(updatedAt);
    if (diff.inMinutes < 1) return 'Updated just now';
    if (diff.inHours < 1) return 'Updated ${diff.inMinutes} min ago';
    if (diff.inDays < 1) return 'Updated ${diff.inHours} h ago';
    if (diff.inDays == 1) return 'Updated yesterday';
    return 'Updated ${diff.inDays} days ago';
  }
}
