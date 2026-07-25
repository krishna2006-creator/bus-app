import 'package:latlong2/latlong.dart';

class BusStop {
  final int id;
  final String name;
  final LatLng location;

  BusStop({required this.id, required this.name, required this.location});

  factory BusStop.fromJson(Map<String, dynamic> json) {
    return BusStop(
      id: json['id'],
      name: json['name'] ?? json['stop_name'] ?? 'Unknown Stop',
      location: LatLng(json['latitude'], json['longitude']),
    );
  }
}

class PredictionResponse {
  final int busId;
  final String busNumber;
  final String routeName;
  final int etaMinutes;
  final double distanceKm;
  final String trafficLevel;
  final bool isToCollege;
  final DateTime arrivalTime;

  PredictionResponse({
    required this.busId,
    required this.busNumber,
    required this.routeName,
    required this.etaMinutes,
    required this.distanceKm,
    required this.trafficLevel,
    required this.isToCollege,
    required this.arrivalTime,
  });

  factory PredictionResponse.fromJson(Map<String, dynamic> json) {
    return PredictionResponse(
      busId: json['bus_id'],
      busNumber: json['bus_number'],
      routeName: json['route_name'] ?? 'Unknown Route',
      etaMinutes: json['eta_minutes'],
      distanceKm: (json['distance_km'] as num).toDouble(),
      trafficLevel: json['traffic_level'],
      isToCollege: json['is_to_college'],
      arrivalTime: DateTime.parse(json['arrival_time']),
    );
  }
}
