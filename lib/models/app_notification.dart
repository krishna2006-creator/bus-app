class AppNotification {
  final String id;
  final String userId;
  final String title;
  final String message;
  final String? busNumber;
  final String? category;
  final String? notificationType; // e.g., 'announcement', 'document', 'feedback', 'request', 'location_started', 'location_stopped'
  final String? targetScreen; // e.g., '/student/announcements', '/student/documents'
  final String? entityId; // ID of the related entity (announcement_id, document_id, etc.)
  final Map<String, dynamic>? payload; // Additional data for navigation
  final DateTime createdAt;
  bool read;
  final bool soundEnabled;

  AppNotification({
    required this.id,
    required this.userId,
    required this.title,
    required this.message,
    this.busNumber,
    this.category,
    this.notificationType,
    this.targetScreen,
    this.entityId,
    this.payload,
    DateTime? createdAt,
    this.read = false,
    this.soundEnabled = true,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'userId': userId,
        'title': title,
        'message': message,
        'busNumber': busNumber,
        'category': category,
        'notificationType': notificationType,
        'targetScreen': targetScreen,
        'entityId': entityId,
        'payload': payload,
        'createdAt': createdAt.toIso8601String(),
        'read': read,
        'soundEnabled': soundEnabled,
      };

  factory AppNotification.fromJson(Map<String, dynamic> json) =>
      AppNotification(
        id: json['id'] as String,
        userId: json['userId'] as String,
        title: json['title'] as String,
        message: json['message'] as String,
        busNumber: json['busNumber'] as String?,
        category: json['category'] as String?,
        notificationType: json['notificationType'] as String?,
        targetScreen: json['targetScreen'] as String?,
        entityId: json['entityId'] as String?,
        payload: json['payload'] as Map<String, dynamic>?,
        createdAt: DateTime.parse(json['createdAt'] as String),
        read: json['read'] as bool? ?? false,
        soundEnabled: json['soundEnabled'] as bool? ?? true,
      );
}