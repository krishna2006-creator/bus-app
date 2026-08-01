import 'dart:async';
import 'dart:math';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:agni_college_bus_tracker/models/bus_location.dart';
import 'package:agni_college_bus_tracker/models/app_notification.dart';
import 'package:agni_college_bus_tracker/services/location_service.dart';
import 'package:agni_college_bus_tracker/services/notification_service.dart';
import 'package:agni_college_bus_tracker/services/auth_service.dart';
import 'package:agni_college_bus_tracker/services/api_service.dart';

class PinnedBusMonitorService extends ChangeNotifier {
  final LocationService _locationService;
  final NotificationService _notificationService;
  final AuthService _authService;

  Timer? _monitorTimer;
  final Set<String> _notifiedBuses = {};
  final Map<String, PinnedBusTrackingData> _trackingData = {};
  final Map<String, DateTime> _lastNotificationTime = {};

  static const double alertDistanceKm = 1.0;
  static const double departureDistanceKm = 2.0;
  static const Duration notificationThrottleDuration = Duration(minutes: 5);

  double _boardingStopLat = 0.0;
  double _boardingStopLng = 0.0;
  Timer? _locationCacheTimer;

  PinnedBusMonitorService(
    this._locationService,
    this._notificationService,
    this._authService,
  );

  Map<String, PinnedBusTrackingData> get trackingData => _trackingData;

  void startMonitoring() {
    debugPrint('🚌 PinnedBusMonitor: Starting monitoring service');
    _updateBoardingStopLocation().then((_) {
      debugPrint('🚌 PinnedBusMonitor: Boarding stop location updated');
    }).catchError((e) {
      debugPrint('🚌 PinnedBusMonitor: Error updating boarding stop: $e');
    });
    
    _monitorTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      _checkPinnedBuses();
    });
    
    _locationCacheTimer = Timer.periodic(const Duration(minutes: 2), (_) {
      _updateBoardingStopLocation();
    });
    
    debugPrint('🚌 PinnedBusMonitor: Monitoring started, checking every 3 seconds');
  }

  void stopMonitoring() {
    _monitorTimer?.cancel();
    _monitorTimer = null;
    _locationCacheTimer?.cancel();
    _locationCacheTimer = null;
    _notifiedBuses.clear();
    _trackingData.clear();
    _lastNotificationTime.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    stopMonitoring();
    super.dispose();
  }

  Future<void> _updateBoardingStopLocation() async {
    try {
      final user = _authService.currentUser;
      if (user == null || user.boardingStopId == null) return;
      final headers = await ApiService.getHeaders();
      final response = await http.get(
        Uri.parse('${ApiService.baseUrl}/stops/${user.boardingStopId}'),
        headers: headers,
      );
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        _boardingStopLat = (data['latitude'] as num?)?.toDouble() ?? 0.0;
        _boardingStopLng = (data['longitude'] as num?)?.toDouble() ?? 0.0;
      }
    } catch (e) {
      debugPrint('Error updating boarding stop location: $e');
    }
  }

  Future<void> _checkPinnedBuses() async {
    try {
      final user = _authService.currentUser;
      if (user == null) {
        debugPrint('🚌 PinnedBusMonitor: No user logged in');
        return;
      }
      
      if (user.pinnedBuses.isEmpty) {
        return;
      }

      final allLocations = _locationService.allLocations;
      debugPrint('🚌 PinnedBusMonitor: Checking ${user.pinnedBuses.length} pinned buses, ${allLocations.length} locations available');

      for (final pinnedBusNumber in user.pinnedBuses) {
        BusLocation? busLocation;
        for (final loc in allLocations.values) {
          if (loc.busNumber == pinnedBusNumber) {
            busLocation = loc;
            break;
          }
        }
        
        if (busLocation == null) {
          debugPrint('🚌 PinnedBusMonitor: Bus $pinnedBusNumber not found in locations');
        }

        if (busLocation == null) {
          if (_trackingData.containsKey(pinnedBusNumber)) {
            _trackingData[pinnedBusNumber]!
              ..distanceKm = -1
              ..etaMinutes = -1
              ..status = 'unknown';
            notifyListeners();
          } else {
            // Bus was not tracked before, no notification needed
          }
          continue;
        }

        // Check if bus just started sharing location (was unknown before)
        final wasUnknown = !_trackingData.containsKey(pinnedBusNumber) ||
            _trackingData[pinnedBusNumber]!.status == 'unknown';

        debugPrint('🚌 PinnedBusMonitor: Bus $pinnedBusNumber - wasUnknown: $wasUnknown, location found');

        // Send notification when bus starts sharing location
        if (wasUnknown) {
          debugPrint('🚌 PinnedBusMonitor: Sending "started" notification for $pinnedBusNumber');
          await _sendBusStartedNotification(pinnedBusNumber);
        }

        final distance = _calculateDistance(
          _boardingStopLat,
          _boardingStopLng,
          busLocation.latitude,
          busLocation.longitude,
        );

        final etaMinutes = (distance / 30.0 * 60).round();

        String status;
        if (distance < 0.1) {
          status = 'ARRIVED';
        } else if (distance < 0.5) {
          status = 'VERY_CLOSE';
        } else if (distance < 1.0) {
          status = 'NEARBY';
        } else if (distance < 3.0) {
          status = 'APPROACHING';
        } else if (distance < 5.0) {
          status = 'ON_THE_WAY';
        } else {
          status = 'EN_ROUTE';
        }

        _trackingData[pinnedBusNumber] = PinnedBusTrackingData(
          busNumber: pinnedBusNumber,
          distanceKm: distance,
          etaMinutes: etaMinutes,
          status: status,
          lastLatitude: busLocation.latitude,
          lastLongitude: busLocation.longitude,
          lastUpdated: DateTime.now(),
        );

        // Throttle nearby notifications to prevent spam
        final now = DateTime.now();
        final lastNotif = _lastNotificationTime[pinnedBusNumber];
        final canSendNearbyNotif = lastNotif == null || 
            now.difference(lastNotif) > notificationThrottleDuration;

        if (distance <= alertDistanceKm &&
            !_notifiedBuses.contains(pinnedBusNumber) &&
            canSendNearbyNotif) {
          await _sendBusNearbyNotification(
              pinnedBusNumber, distance, etaMinutes);
          _notifiedBuses.add(pinnedBusNumber);
          _lastNotificationTime[pinnedBusNumber] = now;
        }
        if (distance > departureDistanceKm &&
            _notifiedBuses.contains(pinnedBusNumber)) {
          _notifiedBuses.remove(pinnedBusNumber);
        }
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error checking pinned buses: $e');
    }
  }

  double _calculateDistance(
      double lat1, double lon1, double lat2, double lon2) {
    if (lat1 == 0 || lon1 == 0) return double.infinity;
    if (lat2 == 0 || lon2 == 0) return double.infinity;
    const double r = 6371;
    final dLat = _toRad(lat2 - lat1);
    final dLon = _toRad(lon2 - lon1);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRad(lat1)) * cos(_toRad(lat2)) * sin(dLon / 2) * sin(dLon / 2);
    return r * 2 * atan2(sqrt(a), sqrt(1 - a));
  }

  double _toRad(double deg) => deg * pi / 180;

  Future<void> _sendBusNearbyNotification(
      String busNumber, double distanceKm, int etaMinutes) async {
    final user = _authService.currentUser;
    if (user == null) return;
    final notification = AppNotification(
      id: 'bus_nearby_${busNumber}_${DateTime.now().millisecondsSinceEpoch}',
      userId: user.id,
      title: 'Bus $busNumber Approaching!',
      message: '${distanceKm.toStringAsFixed(2)}km away - ETA ${etaMinutes}min',
      category: 'BUS_NEARBY',
      createdAt: DateTime.now(),
    );
    await _notificationService.addNotification(notification);
  }

  Future<void> _sendBusStartedNotification(String busNumber) async {
    final user = _authService.currentUser;
    if (user == null) return;

    // Throttle started notifications - only send once per bus per session
    final notificationKey = 'started_$busNumber';
    if (_notifiedBuses.contains(notificationKey)) {
      return; // Already notified for this bus
    }

    final notification = AppNotification(
      id: 'bus_started_${busNumber}_${DateTime.now().millisecondsSinceEpoch}',
      userId: user.id,
      title: 'Bus $busNumber Pinned',
      message: 'Bus $busNumber is now tracking your location',
      category: 'BUS_PINNED',
      notificationType: 'location_started',
      targetScreen: '/track-bus-maps',
      createdAt: DateTime.now(),
    );
    await _notificationService.addNotification(notification);
    _notifiedBuses.add(notificationKey);
  }
}

class PinnedBusTrackingData {
  final String busNumber;
  double distanceKm;
  int etaMinutes;
  String status;
  double lastLatitude;
  double lastLongitude;
  DateTime lastUpdated;

  PinnedBusTrackingData({
    required this.busNumber,
    required this.distanceKm,
    required this.etaMinutes,
    required this.status,
    required this.lastLatitude,
    required this.lastLongitude,
    required this.lastUpdated,
  });

  int get progressPercent {
    if (distanceKm < 0) return 0;
    if (distanceKm <= 0.1) return 100;
    if (distanceKm <= 0.5) return 90;
    if (distanceKm <= 1.0) return 75;
    if (distanceKm <= 3.0) return 50;
    if (distanceKm <= 5.0) return 30;
    if (distanceKm <= 10.0) return 15;
    return 5;
  }

  String get statusLabel {
    switch (status) {
      case 'ARRIVED':
        return 'Bus Arrived!';
      case 'VERY_CLOSE':
        return 'Very Close - Get Ready!';
      case 'NEARBY':
        return 'Nearby - 1 min away';
      case 'APPROACHING':
        return 'Approaching your stop';
      case 'ON_THE_WAY':
        return 'On the way';
      default:
        return 'En route';
    }
  }
}
