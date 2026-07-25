import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart' as latlong;
import 'dart:math' as math;
import 'package:agni_college_bus_tracker/config/app_config.dart';

/// Distance Calculator using Google Maps Directions API for accurate road distance
/// Calculates actual driving distance, not just straight-line distance
class DistanceCalculator {
  static const String directionsBaseUrl =
      'https://maps.googleapis.com/maps/api/directions/json';

  /// Cache to avoid repeated API calls for same route
  static final Map<String, double> _distanceCache = {};
  static final Map<String, int> _durationCache = {};
  static final Map<String, List<latlong.LatLng>> _polylineCache = {};

  /// Calculate distance between two points using Google Maps Directions API
  /// Returns distance in kilometers
  static Future<double> getDistance(
    double startLat,
    double startLng,
    double endLat,
    double endLng,
  ) async {
    try {
      final cacheKey =
          '${startLat.toStringAsFixed(4)}_${startLng.toStringAsFixed(4)}_${endLat.toStringAsFixed(4)}_${endLng.toStringAsFixed(4)}';

      // Check cache first
      if (_distanceCache.containsKey(cacheKey)) {
        debugPrint('Distance from cache: ${_distanceCache[cacheKey]} km');
        return _distanceCache[cacheKey]!;
      }

      final url =
          '$directionsBaseUrl?origin=$startLat,$startLng&destination=$endLat,$endLng&key=${AppConfig.googleMapsApiKey}&mode=driving';

      final response =
          await http.get(Uri.parse(url)).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);

        if (json['status'] == 'OK' && json['routes'].isNotEmpty) {
          final route = json['routes'][0];
          final legs = route['legs'] as List<dynamic>;

          double totalDistance = 0;
          int totalDuration = 0;
          final polylinePoints = <latlong.LatLng>[];

          for (var leg in legs) {
            totalDistance +=
                (leg['distance']['value'] as int) / 1000; // meters to km
            totalDuration +=
                (leg['duration']['value'] as int) ~/ 60; // seconds to minutes
          }

          // Decode polyline for visualization
          if (route['overview_polyline'] != null) {
            final polylineString =
                route['overview_polyline']['points'] as String;
            polylinePoints.addAll(_decodePolyline(polylineString));
          }

          _distanceCache[cacheKey] = totalDistance;
          _durationCache[cacheKey] = totalDuration;
          _polylineCache[cacheKey] = polylinePoints;

          debugPrint(
              'Distance from API: $totalDistance km, Duration: $totalDuration min');
          return totalDistance;
        } else if (json['status'] == 'ZERO_RESULTS') {
          // Fallback to straight-line distance if no route found
          debugPrint('No route found, using straight-line distance');
          return _haversineDistance(startLat, startLng, endLat, endLng);
        }
      }

      // Fallback to straight-line distance on API error
      debugPrint(
          'API error: ${response.statusCode}, using straight-line distance');
      return _haversineDistance(startLat, startLng, endLat, endLng);
    } catch (e) {
      debugPrint('Error calculating distance: $e');
      // Fallback to straight-line distance
      return _haversineDistance(startLat, startLng, endLat, endLng);
    }
  }

  /// Get estimated travel duration in minutes
  static Future<int> getDuration(
    double startLat,
    double startLng,
    double endLat,
    double endLng,
  ) async {
    try {
      final cacheKey =
          '${startLat.toStringAsFixed(4)}_${startLng.toStringAsFixed(4)}_${endLat.toStringAsFixed(4)}_${endLng.toStringAsFixed(4)}';

      if (_durationCache.containsKey(cacheKey)) {
        return _durationCache[cacheKey]!;
      }

      // If we haven't cached it yet, call getDistance which caches duration too
      await getDistance(startLat, startLng, endLat, endLng);

      return _durationCache[cacheKey] ?? 0;
    } catch (e) {
      debugPrint('Error calculating duration: $e');
      return 0;
    }
  }

  /// Get route polyline for visualization
  static Future<List<latlong.LatLng>> getRoutePolyline(
    double startLat,
    double startLng,
    double endLat,
    double endLng,
  ) async {
    try {
      final cacheKey =
          '${startLat.toStringAsFixed(4)}_${startLng.toStringAsFixed(4)}_${endLat.toStringAsFixed(4)}_${endLng.toStringAsFixed(4)}';

      if (_polylineCache.containsKey(cacheKey)) {
        return _polylineCache[cacheKey]!;
      }

      // Fetch if not cached
      await getDistance(startLat, startLng, endLat, endLng);

      return _polylineCache[cacheKey] ?? [];
    } catch (e) {
      debugPrint('Error getting route polyline: $e');
      return [];
    }
  }

  /// Calculate route through multiple waypoints (for boarding points)
  static Future<Map<String, dynamic>> getMultiPointDistance(
    double startLat,
    double startLng,
    List<Map<String, double>> waypoints, // [{lat, lng}, ...]
    double endLat,
    double endLng,
  ) async {
    try {
      String waypointsStr = '';
      for (var wp in waypoints) {
        waypointsStr += '${wp['lat']},${wp['lng']}|';
      }

      // Remove trailing |
      if (waypointsStr.isNotEmpty) {
        waypointsStr = waypointsStr.substring(0, waypointsStr.length - 1);
      }

      final url =
          '$directionsBaseUrl?origin=$startLat,$startLng&destination=$endLat,$endLng&waypoints=$waypointsStr&key=${AppConfig.googleMapsApiKey}&mode=driving';

      final response =
          await http.get(Uri.parse(url)).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);

        if (json['status'] == 'OK' && json['routes'].isNotEmpty) {
          final route = json['routes'][0];
          final legs = route['legs'] as List<dynamic>;

          double totalDistance = 0;
          int totalDuration = 0;

          for (var leg in legs) {
            totalDistance += (leg['distance']['value'] as int) / 1000;
            totalDuration += (leg['duration']['value'] as int) ~/ 60;
          }

          return {
            'distance_km': totalDistance,
            'duration_minutes': totalDuration,
            'waypoint_distances': _getWaypointDistances(legs),
            'waypoint_durations': _getWaypointDurations(legs),
          };
        }
      }

      return {
        'distance_km': 0.0,
        'duration_minutes': 0,
        'waypoint_distances': [],
        'waypoint_durations': [],
      };
    } catch (e) {
      debugPrint('Error calculating multi-point distance: $e');
      return {
        'distance_km': 0.0,
        'duration_minutes': 0,
        'waypoint_distances': [],
        'waypoint_durations': [],
      };
    }
  }

  /// Get individual distances to each waypoint
  static List<double> _getWaypointDistances(List<dynamic> legs) {
    return legs
        .map((leg) => ((leg['distance']['value'] as int) / 1000).toDouble())
        .toList();
  }

  /// Get individual durations to each waypoint
  static List<int> _getWaypointDurations(List<dynamic> legs) {
    return legs.map((leg) => (leg['duration']['value'] as int) ~/ 60).toList();
  }

  /// Simple Haversine distance calculation (fallback, in km)
  static double _haversineDistance(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const R = 6371; // Earth radius in kilometers
    final dLat = _toRad(lat2 - lat1);
    final dLon = _toRad(lon2 - lon1);

    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRad(lat1)) *
            math.cos(_toRad(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);

    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));

    return R * c;
  }

  static double _toRad(double value) => value * math.pi / 180;

  /// Decode Google Maps polyline (compressed format)
  static List<latlong.LatLng> _decodePolyline(String encoded) {
    List<latlong.LatLng> poly = [];
    int index = 0, lat = 0, lng = 0;

    while (index < encoded.length) {
      int b, shift = 0, result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlat = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      lat += dlat;

      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlng = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      lng += dlng;

      poly.add(latlong.LatLng(
        lat / 1e5,
        lng / 1e5,
      ));
    }

    return poly;
  }

  /// Clear cache (call periodically to manage memory)
  static void clearCache() {
    _distanceCache.clear();
    _durationCache.clear();
    _polylineCache.clear();
    debugPrint('Distance calculator cache cleared');
  }

  /// Get cache statistics
  static Map<String, int> getCacheStats() {
    return {
      'distance_entries': _distanceCache.length,
      'duration_entries': _durationCache.length,
      'polyline_entries': _polylineCache.length,
    };
  }
}
