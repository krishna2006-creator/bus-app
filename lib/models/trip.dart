enum TripStatus { active, completed }

class Trip {
  final String id;
  final String busNumber;
  final String driverName;
  final DateTime startTime;
  final DateTime? endTime;
  final TripStatus status;
  final List<String> gpsHistory;
  final DateTime createdAt;
  final DateTime updatedAt;

  Trip({
    required this.id,
    required this.busNumber,
    required this.driverName,
    required this.startTime,
    this.endTime,
    this.status = TripStatus.active,
    List<String>? gpsHistory,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : gpsHistory = gpsHistory ?? [],
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'busNumber': busNumber,
        'driverName': driverName,
        'startTime': startTime.toIso8601String(),
        'endTime': endTime?.toIso8601String(),
        'status': status.name,
        'gpsHistory': gpsHistory,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory Trip.fromJson(Map<String, dynamic> json) => Trip(
        id: json['id'] as String,
        busNumber: json['busNumber'] as String,
        driverName: json['driverName'] as String,
        startTime: DateTime.parse(json['startTime'] as String),
        endTime: json['endTime'] != null
            ? DateTime.parse(json['endTime'] as String)
            : null,
        status: TripStatus.values.firstWhere((e) => e.name == json['status']),
        gpsHistory: (json['gpsHistory'] as List?)?.cast<String>() ?? [],
        createdAt: DateTime.parse(json['createdAt'] as String),
        updatedAt: DateTime.parse(json['updatedAt'] as String),
      );

  Trip copyWith({
    String? id,
    String? busNumber,
    String? driverName,
    DateTime? startTime,
    DateTime? endTime,
    TripStatus? status,
    List<String>? gpsHistory,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) =>
      Trip(
        id: id ?? this.id,
        busNumber: busNumber ?? this.busNumber,
        driverName: driverName ?? this.driverName,
        startTime: startTime ?? this.startTime,
        endTime: endTime ?? this.endTime,
        status: status ?? this.status,
        gpsHistory: gpsHistory ?? this.gpsHistory,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
}
