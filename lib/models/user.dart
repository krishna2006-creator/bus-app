enum UserRole { admin, student, staff, driver }

class User {
  final String id;
  final String? password;
  final UserRole role;
  final String? name;
  final String? email;
  final String? phone;
  final String? assignedBusNumber;
  final int? assignedBusId;
  final List<String> pinnedBuses;
  final int? boardingStopId;
  final DateTime createdAt;
  final DateTime updatedAt;

  User({
    required this.id,
    this.password,
    required this.role,
    this.name,
    this.email,
    this.phone,
    this.assignedBusNumber,
    this.assignedBusId,
    this.boardingStopId,
    List<String>? pinnedBuses,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : pinnedBuses = pinnedBuses ?? [],
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        if (password != null) 'password': password,
        'role': role.name,
        'name': name,
        'email': email,
        'phone': phone,
        'assignedBusNumber': assignedBusNumber,
        'assignedBusId': assignedBusId,
        'pinnedBuses': pinnedBuses,
        'boardingStopId': boardingStopId,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  /// Parse pinned_buses which can be a list of strings (local format)
  /// or a list of objects with bus_number (backend format)
  static List<String> _parsePinnedBuses(dynamic data) {
    if (data == null) return [];
    if (data is List) {
      final result = <String>[];
      for (final item in data) {
        if (item is String) {
          result.add(item);
        } else if (item is Map) {
          final busNumber = item['bus_number'] ?? item['busNumber'];
          if (busNumber != null) {
            result.add(busNumber.toString());
          }
        }
      }
      return result;
    }
    return [];
  }

  factory User.fromJson(Map<String, dynamic> json) {
    final roleStr = json['role'] is String
        ? json['role'] as String
        : json['role'].toString();
    final role = UserRole.values.firstWhere(
      (e) => e.name == roleStr,
      orElse: () => UserRole.student,
    );

    final name = (json['name'] ?? json['full_name']) as String?;

    return User(
      id: json['id'] as String? ?? '',
      password: json['password'] as String?,
      role: role,
      name: name,
      email: json['email'] as String?,
      phone: json['phone'] as String?,
      assignedBusNumber:
          (json['assignedBusNumber'] ?? json['assigned_bus_number']) as String?,
      assignedBusId:
          (json['assigned_bus_id'] ?? json['assignedBusId']) as int?,
      boardingStopId: json['boarding_stop_id'] as int?,
      pinnedBuses:
          _parsePinnedBuses(json['pinned_buses'] ?? json['pinnedBuses']),
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'] as String)
          : DateTime.now(),
      updatedAt: json['updatedAt'] != null
          ? DateTime.parse(json['updatedAt'] as String)
          : DateTime.now(),
    );
  }

  User copyWith({
    String? id,
    String? password,
    UserRole? role,
    String? name,
    String? email,
    String? phone,
    String? assignedBusNumber,
    int? assignedBusId,
    int? boardingStopId,
    List<String>? pinnedBuses,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) =>
      User(
        id: id ?? this.id,
        password: password ?? this.password,
        role: role ?? this.role,
        name: name ?? this.name,
        email: email ?? this.email,
        phone: phone ?? this.phone,
        assignedBusNumber: assignedBusNumber ?? this.assignedBusNumber,
        assignedBusId: assignedBusId ?? this.assignedBusId,
        boardingStopId: boardingStopId ?? this.boardingStopId,
        pinnedBuses: pinnedBuses ?? this.pinnedBuses,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
}