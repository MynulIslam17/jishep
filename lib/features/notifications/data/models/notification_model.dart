import 'package:cloud_firestore/cloud_firestore.dart';

enum NotificationType {
  prayerReminder,
  followUpDue,
  milestone,
  scripture,
  churchNews,
}

class NotificationModel {
  final String id;
  final String title;
  final String message;
  final NotificationType type;
  final DateTime timestamp;
  final bool isRead;
  final String? actionRoute;
  final Map<String, dynamic>? payload;

  NotificationModel({
    required this.id,
    required this.title,
    required this.message,
    required this.type,
    required this.timestamp,
    this.isRead = false,
    this.actionRoute,
    this.payload,
  });

  factory NotificationModel.fromJson(Map<String, dynamic> json) {
    return NotificationModel(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      message: json['message']?.toString() ?? '',
      type: _typeFromString(json['type']?.toString()),
      timestamp: json['timestamp'] != null
          ? DateTime.tryParse(json['timestamp'].toString()) ?? DateTime.now()
          : DateTime.now(),
      isRead: json['isRead'] == true,
      actionRoute: json['actionRoute']?.toString(),
      payload: json['payload'] is Map<String, dynamic> ? json['payload'] as Map<String, dynamic> : null,
    );
  }

  factory NotificationModel.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? const <String, dynamic>{};
    final timestamp = data['timestamp'];
    return NotificationModel(
      id: doc.id,
      title: data['title']?.toString() ?? '',
      message: data['message']?.toString() ?? '',
      type: _typeFromString(data['type']?.toString()),
      timestamp: timestamp is Timestamp ? timestamp.toDate() : DateTime.now(),
      isRead: data['isRead'] == true,
      actionRoute: data['actionRoute']?.toString(),
      payload: data['payload'] is Map<String, dynamic>
          ? data['payload'] as Map<String, dynamic>
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'message': message,
      'type': type.name,
      'timestamp': timestamp.toIso8601String(),
      'isRead': isRead,
      'actionRoute': actionRoute,
      'payload': payload,
    };
  }

  NotificationModel copyWith({
    String? id,
    String? title,
    String? message,
    NotificationType? type,
    DateTime? timestamp,
    bool? isRead,
    String? actionRoute,
    Map<String, dynamic>? payload,
  }) {
    return NotificationModel(
      id: id ?? this.id,
      title: title ?? this.title,
      message: message ?? this.message,
      type: type ?? this.type,
      timestamp: timestamp ?? this.timestamp,
      isRead: isRead ?? this.isRead,
      actionRoute: actionRoute ?? this.actionRoute,
      payload: payload ?? this.payload,
    );
  }

  static NotificationType _typeFromString(String? typeStr) {
    return switch (typeStr) {
      'prayerReminder' => NotificationType.prayerReminder,
      'followUpDue' => NotificationType.followUpDue,
      'milestone' => NotificationType.milestone,
      'scripture' => NotificationType.scripture,
      'churchNews' => NotificationType.churchNews,
      _ => NotificationType.prayerReminder,
    };
  }
}
