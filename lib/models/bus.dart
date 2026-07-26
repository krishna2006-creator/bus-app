class Bus {
  final int id;
  final String busNumber;
  final String route;
  final String? driverName;
  final String? driverPhone;
  final bool isOperating;
  final List<String> stops;
  final int studentCount;
  final DateTime createdAt;
  final DateTime updatedAt;

  Bus({
    required this.id,
    required this.busNumber,
    required this.route,
    this.driverName,
    this.driverPhone,
    this.isOperating = true,
    List<String>? stops,
    this.studentCount = 0,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : stops = stops ?? [],
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  bool get hasDriver => driverName != null && driverName!.isNotEmpty;

  Map<String, dynamic> toJson() => {
        'id': id,
        'busNumber': busNumber,
        'route': route,
        'driverName': driverName,
        'driverPhone': driverPhone,
        'isOperating': isOperating,
        'stops': stops,
        'studentCount': studentCount,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory Bus.fromJson(Map<String, dynamic> json) => Bus(
        id: json['id'] as int? ?? json['bus_id'] as int? ?? 0,
        busNumber: (json['busNumber'] as String?) ??
            (json['bus_number'] as String?) ??
            '',
        route:
            (json['route'] as String?) ?? (json['bus_route'] as String?) ?? '',
        driverName:
            json['driverName'] as String? ?? json['driver_name'] as String?,
        driverPhone:
            json['driverPhone'] as String? ?? json['driver_phone'] as String?,
        isOperating: json['isOperating'] as bool? ??
            json['is_operating'] as bool? ??
            true,
        stops: (json['stops'] as List?)?.cast<String>() ??
            (json['bus_stops'] as List?)?.cast<String>() ??
            [],
        studentCount:
            json['studentCount'] as int? ?? json['student_count'] as int? ?? 0,
        createdAt: json['createdAt'] != null
            ? DateTime.parse(json['createdAt'] as String)
            : json['created_at'] != null
                ? DateTime.parse(json['created_at'] as String)
                : DateTime.now(),
        updatedAt: json['updatedAt'] != null
            ? DateTime.parse(json['updatedAt'] as String)
            : json['updated_at'] != null
                ? DateTime.parse(json['updated_at'] as String)
                : DateTime.now(),
      );

  Bus copyWith({
    int? id,
    String? busNumber,
    String? route,
    String? driverName,
    String? driverPhone,
    bool? isOperating,
    List<String>? stops,
    int? studentCount,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) =>
      Bus(
        id: id ?? this.id,
        busNumber: busNumber ?? this.busNumber,
        route: route ?? this.route,
        driverName: driverName ?? this.driverName,
        driverPhone: driverPhone ?? this.driverPhone,
        isOperating: isOperating ?? this.isOperating,
        stops: stops ?? this.stops,
        studentCount: studentCount ?? this.studentCount,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
}
