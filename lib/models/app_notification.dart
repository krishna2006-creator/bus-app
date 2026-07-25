class AppNotification {
  final String id;
  final String userId;
  final String title;
  final String message;
  final String? busNumber;
  final String? category;
  final DateTime createdAt;
  bool read;

  AppNotification({
    required this.id,
    required this.userId,
    required this.title,
    required this.message,
    this.busNumber,
    this.category,
    DateTime? createdAt,
    this.read = false,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'userId': userId,
        'title': title,
        'message': message,
        'busNumber': busNumber,
        'category': category,
        'createdAt': createdAt.toIso8601String(),
        'read': read,
      };

  factory AppNotification.fromJson(Map<String, dynamic> json) =>
      AppNotification(
        id: json['id'] as String,
        userId: json['userId'] as String,
        title: json['title'] as String,
        message: json['message'] as String,
        busNumber: json['busNumber'] as String?,
        category: json['category'] as String?,
        createdAt: DateTime.parse(json['createdAt'] as String),
        read: json['read'] as bool? ?? false,
      );
}
