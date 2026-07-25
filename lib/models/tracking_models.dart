import 'package:latlong2/latlong.dart';

/// Represents a boarding point for student pickup
class BoardingPoint {
  final String id;
  final String name;
  final double latitude;
  final double longitude;
  final String address;
  final int sequence; // Order in the route

  BoardingPoint({
    required this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.address,
    required this.sequence,
  });

  factory BoardingPoint.fromJson(Map<String, dynamic> json) {
    return BoardingPoint(
      id: json['id'] as String,
      name: json['name'] as String,
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      address: json['address'] as String,
      sequence: json['sequence'] as int,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'latitude': latitude,
        'longitude': longitude,
        'address': address,
        'sequence': sequence,
      };
}

/// Represents a real-time tracking session for a student
class TrackingSession {
  final String id;
  final String studentId;
  final String busId;
  final String boardingPointId;
  final DateTime startTime;
  DateTime? endTime;
  TrackingStatus
      status; // tracking_to_boarding, at_boarding, tracking_to_college, completed
  double distanceToBus; // in km
  double distanceToBoarding; // in km (if not at boarding yet)
  double totalDistanceToCollege; // in km (from current to college)
  int estimatedMinutesToBus;
  int estimatedMinutesToCollege;

  TrackingSession({
    required this.id,
    required this.studentId,
    required this.busId,
    required this.boardingPointId,
    required this.startTime,
    this.endTime,
    this.status = TrackingStatus.trackingToBoarding,
    this.distanceToBus = 0.0,
    this.distanceToBoarding = 0.0,
    this.totalDistanceToCollege = 0.0,
    this.estimatedMinutesToBus = 0,
    this.estimatedMinutesToCollege = 0,
  });

  factory TrackingSession.fromJson(Map<String, dynamic> json) {
    return TrackingSession(
      id: json['id'] as String,
      studentId: json['student_id'] as String,
      busId: json['bus_id'] as String,
      boardingPointId: json['boarding_point_id'] as String,
      startTime: DateTime.parse(json['start_time'] as String),
      endTime: json['end_time'] != null
          ? DateTime.parse(json['end_time'] as String)
          : null,
      status: TrackingStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => TrackingStatus.trackingToBoarding,
      ),
      distanceToBus: (json['distance_to_bus'] as num?)?.toDouble() ?? 0.0,
      distanceToBoarding:
          (json['distance_to_boarding'] as num?)?.toDouble() ?? 0.0,
      totalDistanceToCollege:
          (json['total_distance_to_college'] as num?)?.toDouble() ?? 0.0,
      estimatedMinutesToBus: json['estimated_minutes_to_bus'] as int? ?? 0,
      estimatedMinutesToCollege:
          json['estimated_minutes_to_college'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'student_id': studentId,
        'bus_id': busId,
        'boarding_point_id': boardingPointId,
        'start_time': startTime.toIso8601String(),
        'end_time': endTime?.toIso8601String(),
        'status': status.name,
        'distance_to_bus': distanceToBus,
        'distance_to_boarding': distanceToBoarding,
        'total_distance_to_college': totalDistanceToCollege,
        'estimated_minutes_to_bus': estimatedMinutesToBus,
        'estimated_minutes_to_college': estimatedMinutesToCollege,
      };

  bool isActive() => status != TrackingStatus.completed;
}

enum TrackingStatus {
  trackingToBoarding,
  atBoarding,
  trackingToCollege,
  completed,
}

/// Represents a bus route with waypoints
class BusRoute {
  final String busId;
  final List<BoardingPoint> boardingPoints;
  final LatLng collegeLocation;
  final List<LatLng> routePolyline;
  final double totalDistanceKm;

  BusRoute({
    required this.busId,
    required this.boardingPoints,
    required this.collegeLocation,
    required this.routePolyline,
    required this.totalDistanceKm,
  });

  factory BusRoute.fromJson(Map<String, dynamic> json) {
    final points = (json['boarding_points'] as List<dynamic>?)
            ?.map((p) => BoardingPoint.fromJson(p as Map<String, dynamic>))
            .toList() ??
        [];

    final polyline = (json['route_polyline'] as List<dynamic>?)?.map((p) {
          final pMap = p as Map<String, dynamic>;
          return LatLng(
            (pMap['latitude'] as num).toDouble(),
            (pMap['longitude'] as num).toDouble(),
          );
        }).toList() ??
        [];

    return BusRoute(
      busId: json['bus_id'] as String,
      boardingPoints: points,
      collegeLocation: LatLng(
        (json['college_latitude'] as num).toDouble(),
        (json['college_longitude'] as num).toDouble(),
      ),
      routePolyline: polyline,
      totalDistanceKm: (json['total_distance_km'] as num).toDouble(),
    );
  }
}

/// Real-time location update for buses and students
class LiveLocation {
  final String entityId; // bus_id or student_id
  final String entityType; // 'bus' or 'student'
  final double latitude;
  final double longitude;
  final double speed; // km/h
  final double bearing;
  final DateTime timestamp;
  final double accuracy;

  LiveLocation({
    required this.entityId,
    required this.entityType,
    required this.latitude,
    required this.longitude,
    required this.speed,
    required this.bearing,
    required this.timestamp,
    required this.accuracy,
  });

  factory LiveLocation.fromJson(Map<String, dynamic> json) {
    return LiveLocation(
      entityId: json['entity_id'] as String,
      entityType: json['entity_type'] as String,
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      speed: (json['speed'] as num?)?.toDouble() ?? 0.0,
      bearing: (json['bearing'] as num?)?.toDouble() ?? 0.0,
      timestamp: DateTime.parse(json['timestamp'] as String),
      accuracy: (json['accuracy'] as num?)?.toDouble() ?? 0.0,
    );
  }

  Map<String, dynamic> toJson() => {
        'entity_id': entityId,
        'entity_type': entityType,
        'latitude': latitude,
        'longitude': longitude,
        'speed': speed,
        'bearing': bearing,
        'timestamp': timestamp.toIso8601String(),
        'accuracy': accuracy,
      };

  LatLng toLatLng() => LatLng(latitude, longitude);
}
