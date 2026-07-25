enum RequestType { missedBus, stopBus, delayBus, busIssue }

enum RequestStatus { pending, approved, rejected }

class Request {
  final String id;
  final String userId;
  final String userName;
  final String busNumber;
  final RequestType type;
  final String message;
  final RequestStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;

  Request({
    required this.id,
    required this.userId,
    required this.userName,
    required this.busNumber,
    required this.type,
    required this.message,
    this.status = RequestStatus.pending,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'userId': userId,
        'userName': userName,
        'busNumber': busNumber,
        'type': type.name,
        'message': message,
        'status': status.name,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory Request.fromJson(Map<String, dynamic> json) => Request(
        id: json['id'] as String,
        userId: json['userId'] as String,
        userName: json['userName'] as String,
        busNumber: json['busNumber'] as String,
        type: RequestType.values.firstWhere((e) => e.name == json['type']),
        message: json['message'] as String,
        status:
            RequestStatus.values.firstWhere((e) => e.name == json['status']),
        createdAt: DateTime.parse(json['createdAt'] as String),
        updatedAt: DateTime.parse(json['updatedAt'] as String),
      );

  Request copyWith({
    String? id,
    String? userId,
    String? userName,
    String? busNumber,
    RequestType? type,
    String? message,
    RequestStatus? status,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) =>
      Request(
        id: id ?? this.id,
        userId: userId ?? this.userId,
        userName: userName ?? this.userName,
        busNumber: busNumber ?? this.busNumber,
        type: type ?? this.type,
        message: message ?? this.message,
        status: status ?? this.status,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
}
