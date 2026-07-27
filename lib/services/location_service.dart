import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:agni_college_bus_tracker/models/bus_location.dart';
import 'package:agni_college_bus_tracker/models/user.dart';
import 'package:agni_college_bus_tracker/services/api_service.dart';

class LocationService extends ChangeNotifier {
  static const _driverLocationsKey = 'driver_locations';
  static const _studentLocationsKey = 'student_locations';

  Map<String, BusLocation> _driverLocations = {};
  Map<String, BusLocation> _studentLocations = {};
  Timer? _cleanupTimer;
  Timer? _syncTimer;
  StreamSubscription? _websocketSubscription;

  Map<String, BusLocation> get driverLocations => _driverLocations;
  Map<String, BusLocation> get studentLocations => _studentLocations;

  Map<String, BusLocation> get allLocations => {
        ..._studentLocations,
        ..._driverLocations,
      };

  void listenToWebSocketUpdates(Stream<Map<String, dynamic>> messageStream) {
    _websocketSubscription?.cancel();
    _websocketSubscription = messageStream.listen((data) {
      try {
        final type = data['type'] as String? ?? '';

        // Handle STOP_SHARING - remove marker immediately
        if (type == 'STOP_SHARING') {
          final busId = data['bus_id']?.toString() ?? '';
          if (busId.isNotEmpty) {
            removeLocation(busId);
            debugPrint('🗑️ Removed $busId via STOP_SHARING');
          }
          return;
        }

        if (type == 'LOCATION_CLEARED') {
          final busId = data['bus_id']?.toString() ?? '';
          if (busId.isNotEmpty) {
            removeLocation(busId);
            debugPrint('🗑️ Cleared location for bus $busId');
          }
          return;
        }

        if (type == 'LOCATION_UPDATE') {
          final latitude = (data['latitude'] as num?)?.toDouble() ?? 0.0;
          final longitude = (data['longitude'] as num?)?.toDouble() ?? 0.0;
          final speed = (data['speed'] as num?)?.toDouble() ?? 0.0;
          final payload = data['payload'] as Map<String, dynamic>?;
          final role = (data['role'] as String?)?.toLowerCase() ??
              (payload?['user_role'] as String?)?.toLowerCase() ??
              (payload?['role'] as String?)?.toLowerCase() ??
              '';

          final payloadBusId =
              payload?['bus_id']?.toString() ?? payload?['id']?.toString();
          final payloadLat = (payload?['latitude'] as num?)?.toDouble();
          final payloadLng = (payload?['longitude'] as num?)?.toDouble();

          final effectiveBusId = data['bus_id']?.toString() ??
              data['id']?.toString() ??
              payloadBusId ??
              '';

          final effectiveLatitude =
              latitude != 0.0 ? latitude : (payloadLat ?? 0.0);
          final effectiveLongitude =
              longitude != 0.0 ? longitude : (payloadLng ?? 0.0);

          if (effectiveBusId.isNotEmpty &&
              effectiveLatitude != 0.0 &&
              effectiveLongitude != 0.0) {
            final location = BusLocation(
              busNumber: effectiveBusId,
              latitude: effectiveLatitude,
              longitude: effectiveLongitude,
              speed: speed,
              timestamp: DateTime.now(),
              userType: role == 'driver' ? UserRole.driver : UserRole.student,
              isSharedByStudent: (payload?['is_public'] == true) ||
                  (data['is_public'] == true) ||
                  role == 'student',
            );
            updateLocation(location);
          }
        }
      } catch (e) {
        debugPrint('Error processing WebSocket location update: $e');
      }
    });
  }

  Future<void> initialize() async {
    await _loadLocations();
    await fetchAllLatestLocations();

    _cleanupTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      final now = DateTime.now();
      bool changed = false;
      _driverLocations.removeWhere((key, value) {
        if (now.difference(value.timestamp).inMinutes > 10) {
          changed = true;
          return true;
        }
        return false;
      });
      _studentLocations.removeWhere((key, value) {
        if (now.difference(value.timestamp).inMinutes > 5) {
          changed = true;
          return true;
        }
        return false;
      });
      if (changed) notifyListeners();
    });
  }

  Future<void> fetchAllLatestLocations() async {
    try {
      final response = await http.get(
        Uri.parse('${ApiService.baseUrl}/tracking/locations/all-latest'),
        headers: await ApiService.getHeaders(),
      );
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        for (var item in data) {
          try {
            final location = BusLocation(
              busNumber: item['entity_id']?.toString() ?? '',
              latitude: (item['latitude'] as num?)?.toDouble() ?? 0.0,
              longitude: (item['longitude'] as num?)?.toDouble() ?? 0.0,
              speed: (item['speed'] as num?)?.toDouble() ?? 0.0,
              timestamp: DateTime.parse(item['timestamp'] as String? ??
                  DateTime.now().toIso8601String()),
              userType: UserRole.driver,
              isSharedByStudent: false,
            );
            _driverLocations[location.busNumber] = location;
          } catch (e) {
            debugPrint('Error parsing location: $e');
          }
        }
        await _saveLocations();
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error fetching latest locations: $e');
    }
  }

  Future<void> updateLocation(BusLocation newLocation) async {
    if (newLocation.userType == UserRole.driver) {
      _driverLocations[newLocation.busNumber] = newLocation;
    } else {
      _studentLocations[newLocation.busNumber] = newLocation;
    }
    await _saveLocations();
    notifyListeners();
  }

  Future<void> removeLocation(String busNumber) async {
    final removedFromDriver = _driverLocations.remove(busNumber) != null;
    final removedFromStudent = _studentLocations.remove(busNumber) != null;
    if (removedFromDriver || removedFromStudent) {
      await _saveLocations();
      notifyListeners();
    }
  }

  Future<void> _loadLocations() async {
    final prefs = await SharedPreferences.getInstance();
    final driverLocationsJson = prefs.getString(_driverLocationsKey);
    if (driverLocationsJson != null) {
      try {
        final Map<String, dynamic> decoded = json.decode(driverLocationsJson);
        _driverLocations = decoded.map(
          (key, value) => MapEntry(key, BusLocation.fromJson(value)),
        );
      } catch (e) {
        debugPrint('Error loading driver locations: $e');
      }
    }
    final studentLocationsJson = prefs.getString(_studentLocationsKey);
    if (studentLocationsJson != null) {
      try {
        final Map<String, dynamic> decoded = json.decode(studentLocationsJson);
        _studentLocations = decoded.map(
          (key, value) => MapEntry(key, BusLocation.fromJson(value)),
        );
      } catch (e) {
        debugPrint('Error loading student locations: $e');
      }
    }
    notifyListeners();
  }

  Future<void> _saveLocations() async {
    final prefs = await SharedPreferences.getInstance();
    final driverLocationsJson = json.encode(
      _driverLocations.map((key, value) => MapEntry(key, value.toJson())),
    );
    await prefs.setString(_driverLocationsKey, driverLocationsJson);
    final studentLocationsJson = json.encode(
      _studentLocations.map((key, value) => MapEntry(key, value.toJson())),
    );
    await prefs.setString(_studentLocationsKey, studentLocationsJson);
  }

  BusLocation? getBestLocationForBus(String busNumber) {
    if (_driverLocations.containsKey(busNumber)) {
      return _driverLocations[busNumber];
    }
    return _studentLocations[busNumber];
  }

  /// Returns only the location for the bus that is assigned to the user.
  /// This ensures that when sharing location, only the assigned bus shows,
  /// not other buses that might be sharing locations simultaneously.
  BusLocation? getLocationsForAssignedBus(User user) {
    if (user.assignedBusId == null && user.assignedBusNumber == null) {
      return null;
    }
    final busNumber = user.assignedBusNumber ?? user.assignedBusId.toString();
    return getBestLocationForBus(busNumber);
  }

  Future<void> refreshBusLocations() async {
    await _loadLocations();
    notifyListeners();
  }

  @override
  void dispose() {
    _websocketSubscription?.cancel();
    _cleanupTimer?.cancel();
    _syncTimer?.cancel();
    super.dispose();
  }
}
