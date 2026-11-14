import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gps_cielo/core/data/geo_record.dart';

class HouseholdModel {
  final String id;
  final int number;

  /// The name the user gave this household (private to them, stored in
  /// their `household_status/{id}`), or null when none was set.
  final String? residentName;
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
    String? residentName,
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
  }) : residentName = cleanName(residentName);

  /// Longest resident name stored (Firestore rules allow 120).
  static const int maxNameLength = 120;

  /// Shown when the user has not named the household.
  static const String unnamed = 'Neighbor';

  static final RegExp _placeholder = RegExp(
    r'^(resident|neighbor|demo household \d{3})$',
    caseSensitive: false,
  );

  /// A name as stored: trimmed and at most [maxNameLength] characters, or
  /// null when empty or a placeholder ("Resident", "Neighbor", "Demo
  /// Household NNN" — written by older versions, not by the user).
  static String? cleanName(Object? raw) {
    final name = raw?.toString().trim() ?? '';
    if (name.isEmpty || _placeholder.hasMatch(name)) return null;
    return name.length > maxNameLength
        ? name.substring(0, maxNameLength).trim()
        : name;
  }

  /// The title shown for the household: its name, or "Neighbor".
  String get displayName => residentName ?? unnamed;

  /// A copy with [name] as the resident name (null or empty removes it).
  HouseholdModel withName(String? name) {
    return HouseholdModel(
      id: id,
      number: number,
      residentName: name,
      address: address,
      cityStateZip: cityStateZip,
      isPrayed: isPrayed,
      isVisited: isVisited,
      isInvited: isInvited,
      hasFollowUp: hasFollowUp,
      followUpDate: followUpDate,
      lastUpdated: lastUpdated,
      notes: notes,
      latitude: latitude,
      longitude: longitude,
      prayedAt: prayedAt,
      updatedAt: updatedAt,
    );
  }

  String get fullAddress =>
      cityStateZip.isEmpty ? address : '$address, $cityStateZip';

  /// Whether [status] counts as prayed for in the cycle that started at
  /// [cycleStart] (null = every prayer counts).
  static bool prayedInCycle(
    Map<String, dynamic>? status,
    DateTime? cycleStart,
  ) {
    if (status?['isPrayed'] != true) return false;
    if (cycleStart == null) return true;
    final prayedAt = _toDate(status?['prayedAt']);
    return prayedAt != null && !prayedAt.isBefore(cycleStart);
  }

  /// True when prayed for on the same calendar day as [now].
  bool prayedOn(DateTime now) {
    final at = prayedAt;
    return isPrayed &&
        at != null &&
        at.year == now.year &&
        at.month == now.month &&
        at.day == now.day;
  }

  /// True when any status is set (shown on the Follow-up screen).
  bool get hasActivity =>
      isPrayed ||
      isVisited ||
      isInvited ||
      hasFollowUp ||
      (notes?.trim().isNotEmpty ?? false);

  /// A household known only from the user's status document (it may be
  /// outside the area currently loaded). The status stores name and address.
  factory HouseholdModel.fromStatus({
    required String id,
    required Map<String, dynamic> status,
    required int number,
    DateTime? cycleStart,
  }) {
    final updatedAt = _toDate(status['updatedAt']);
    return HouseholdModel(
      id: id,
      number: number,
      residentName: status['residentName']?.toString(),
      address: status['address']?.toString() ?? '',
      isPrayed: prayedInCycle(status, cycleStart),
      isVisited: status['isVisited'] == true,
      isInvited: status['isInvited'] == true,
      hasFollowUp: status['hasFollowUp'] == true,
      followUpDate: status['followUpDate']?.toString(),
      notes: status['notes']?.toString(),
      prayedAt: _toDate(status['prayedAt']),
      updatedAt: updatedAt,
      lastUpdated: _describeUpdatedAt(updatedAt),
    );
  }

  /// Builds a household from the shared `households/{id}` document merged with
  /// the signed-in user's `household_status/{id}` document (if any).
  factory HouseholdModel.fromFirestore({
    required DocumentSnapshot<Map<String, dynamic>> doc,
    Map<String, dynamic>? status,
    required int number,
    DateTime? cycleStart,
  }) {
    final data = doc.data() ?? const <String, dynamic>{};
    final geo = data['geo'];
    final geopoint = geo is Map ? geo['geopoint'] : null;
    final updatedAt = _toDate(status?['updatedAt']);

    return HouseholdModel(
      id: doc.id,
      number: number,
      residentName: status?['residentName']?.toString(),
      address: data['address']?.toString() ?? '',
      cityStateZip: data['cityStateZip']?.toString() ?? '',
      latitude: geopoint is GeoPoint ? geopoint.latitude : 0,
      longitude: geopoint is GeoPoint ? geopoint.longitude : 0,
      isPrayed: prayedInCycle(status, cycleStart),
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

  /// Builds a household from a [GeoRecord] (a `households` document or an
  /// Overture cell entry) merged with the signed-in user's status document.
  factory HouseholdModel.fromRecord({
    required GeoRecord record,
    Map<String, dynamic>? status,
    required int number,
    DateTime? cycleStart,
  }) {
    final updatedAt = _toDate(status?['updatedAt']);
    return HouseholdModel(
      id: record.id,
      number: number,
      residentName: status?['residentName']?.toString(),
      address: record.address,
      cityStateZip: record.cityStateZip,
      latitude: record.latitude,
      longitude: record.longitude,
      isPrayed: prayedInCycle(status, cycleStart),
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
      residentName: json['residentName']?.toString(),
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
  /// `residentName` is not included: it is written only when the user
  /// changes it (see `HouseholdRepository.saveStatus`).
  Map<String, dynamic> toStatusFirestore() {
    return {
      'isPrayed': isPrayed,
      'isVisited': isVisited,
      'isInvited': isInvited,
      'hasFollowUp': hasFollowUp,
      'followUpDate': hasFollowUp ? followUpDate : null,
      'notes': notes,
      'address': fullAddress,
    };
  }

  bool hasSameStatusAs(HouseholdModel other) {
    return isPrayed == other.isPrayed &&
        isVisited == other.isVisited &&
        isInvited == other.isInvited &&
        hasFollowUp == other.hasFollowUp &&
        followUpDate == other.followUpDate &&
        notes == other.notes &&
        residentName == other.residentName;
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
