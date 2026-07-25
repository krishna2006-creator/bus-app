enum AnnouncementTarget { students, staff, drivers, all }

class Announcement {
  final String id;
  final String title;
  final String message;
  final AnnouncementTarget target;
  final String? busNumber;
  final String? attachmentUrl;
  final DateTime createdAt;

  Announcement({
    required this.id,
    required this.title,
    required this.message,
    required this.target,
    this.busNumber,
    this.attachmentUrl,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'message': message,
        'target': target.name,
        'busNumber': busNumber,
        'attachmentUrl': attachmentUrl,
        'createdAt': createdAt.toIso8601String(),
      };

  factory Announcement.fromJson(Map<String, dynamic> json) {
    final idVal = json['id'];
    final idStr = idVal?.toString() ?? '';

    AnnouncementTarget targetEnum = AnnouncementTarget.all;
    final targetStr = json['target'] ?? json['target_role'];
    if (targetStr != null) {
      final normalizedTarget = targetStr.toString().toLowerCase();
      if (normalizedTarget == 'students' || normalizedTarget == 'student') {
        targetEnum = AnnouncementTarget.students;
      } else if (normalizedTarget == 'staff') {
        targetEnum = AnnouncementTarget.staff;
      } else if (normalizedTarget == 'drivers' || normalizedTarget == 'driver') {
        targetEnum = AnnouncementTarget.drivers;
      } else {
        targetEnum = AnnouncementTarget.all;
      }
    }

    final dateStr = json['createdAt'] ?? json['created_at'];
    final createdAtVal = dateStr != null ? DateTime.parse(dateStr as String) : DateTime.now();

    return Announcement(
      id: idStr,
      title: (json['title'] ?? '') as String,
      message: (json['message'] ?? '') as String,
      target: targetEnum,
      busNumber: json['busNumber'] as String?,
      attachmentUrl: json['attachmentUrl'] as String?,
      createdAt: createdAtVal,
    );
  }
}
