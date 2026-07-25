import 'package:agni_college_bus_tracker/models/user.dart';
import 'package:agni_college_bus_tracker/config/app_config.dart';

class BusLocation {
  final String busNumber;
  final double latitude;
  final double longitude;
  final double speed;
  final DateTime timestamp;
  final UserRole userType;
  final String userName;
  final bool isSharedByStudent;

  BusLocation({
    required this.busNumber,
    required this.latitude,
    required this.longitude,
    required this.speed,
    required this.timestamp,
    required this.userType,
    this.userName = 'Unknown',
    this.isSharedByStudent = false,
  }) {
    // Validate coordinates
    _validateCoordinates();
  }

  /// Validates GPS coordinates are within valid ranges
  void _validateCoordinates() {
    if (latitude < AppConfig.minLatitude || latitude > AppConfig.maxLatitude) {
      throw ArgumentError(
          'Invalid latitude: $latitude (must be between ${AppConfig.minLatitude} and ${AppConfig.maxLatitude})');
    }
    if (longitude < AppConfig.minLongitude ||
        longitude > AppConfig.maxLongitude) {
      throw ArgumentError(
          'Invalid longitude: $longitude (must be between ${AppConfig.minLongitude} and ${AppConfig.maxLongitude})');
    }
    if (speed < AppConfig.minSpeed) {
      throw ArgumentError(
          'Invalid speed: $speed (must be >= ${AppConfig.minSpeed})');
    }
  }

  factory BusLocation.fromJson(Map<String, dynamic> json) {
    return BusLocation(
      busNumber: json['busNumber'] as String,
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      speed: (json['speed'] as num?)?.toDouble() ?? 0.0,
      timestamp: DateTime.parse(json['timestamp'] as String),
      userType: UserRole.values.byName(json['userType'] as String),
      userName: json['userName'] as String? ?? 'Unknown',
      isSharedByStudent: json['isSharedByStudent'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'busNumber': busNumber,
        'latitude': latitude,
        'longitude': longitude,
        'speed': speed,
        'timestamp': timestamp.toIso8601String(),
        'userType': userType.name,
        'userName': userName,
        'isSharedByStudent': isSharedByStudent,
      };
}
