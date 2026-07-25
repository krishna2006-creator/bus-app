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
        id: json['id'] as int? ?? 0,
        busNumber: json['busNumber'] as String,
        route: json['route'] as String,
        driverName: json['driverName'] as String?,
        driverPhone: json['driverPhone'] as String?,
        isOperating: json['isOperating'] as bool? ?? true,
        stops: (json['stops'] as List?)?.cast<String>() ?? [],
        studentCount: json['studentCount'] as int? ?? 0,
        createdAt: DateTime.parse(json['createdAt'] as String),
        updatedAt: DateTime.parse(json['updatedAt'] as String),
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
