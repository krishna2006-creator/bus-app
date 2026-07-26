class Feedback {
  final String id;
  final String userId;
  final String userName;
  final String userRole;
  final String subject;
  final String message;
  final String? reply;
  final bool replied;
  final DateTime createdAt;
  final DateTime? repliedAt;

  Feedback({
    required this.id,
    required this.userId,
    required this.userName,
    required this.userRole,
    required this.subject,
    required this.message,
    this.reply,
    this.replied = false,
    DateTime? createdAt,
    this.repliedAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'userId': userId,
        'userName': userName,
        'userRole': userRole,
        'subject': subject,
        'message': message,
        'reply': reply,
        'replied': replied,
        'createdAt': createdAt.toIso8601String(),
        'repliedAt': repliedAt?.toIso8601String(),
      };

  factory Feedback.fromJson(Map<String, dynamic> json) {
    DateTime? repliedAt;
    if (json['repliedAt'] != null) {
      repliedAt = DateTime.tryParse(json['repliedAt'].toString());
    }
    return Feedback(
      id: json['id']?.toString() ??
          DateTime.now().millisecondsSinceEpoch.toString(),
      userId: json['userId']?.toString() ?? '',
      userName: json['userName']?.toString() ?? 'Unknown',
      userRole: json['userRole']?.toString() ?? 'student',
      subject: json['subject']?.toString() ?? '',
      message: json['message']?.toString() ?? '',
      reply: json['reply']?.toString(),
      replied: json['replied'] == true,
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'].toString())
          : DateTime.now(),
      repliedAt: repliedAt,
    );
  }
}
