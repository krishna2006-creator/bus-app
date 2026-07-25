import 'package:flutter/foundation.dart';
import 'dart:async';
import 'package:agni_college_bus_tracker/models/tracking_models.dart';
import 'package:agni_college_bus_tracker/services/api_service.dart';
import 'package:agni_college_bus_tracker/services/distance_calculator.dart'
    as dist;
import 'package:agni_college_bus_tracker/config/app_config.dart';

/// Real-time Live Tracking Service
/// Manages tracking sessions for students following buses to boarding points and college
class LiveTrackingService extends ChangeNotifier {
  // Active tracking sessions
  final Map<String, TrackingSession> _activeSessions = {};

  // Real-time location streams
  final Map<String, LiveLocation> _latestLocations = {};

  // Bus routes cache
  final Map<String, BusRoute> _busRoutes = {};

  // Update streams
  final Map<String, StreamSubscription> _updateSubscriptions = {};

  // Pinned buses (for quick access and auto-opening)
  final Set<String> _pinnedBusIds = {};

  // Currently focused bus for the tracking UI (triggers auto-open)
  String? _focusedBusId;

  // Polling for bus location updates
  Timer? _pollingTimer;
  final Duration _pollingInterval = const Duration(seconds: 5);

  LiveTrackingService();

  String? get focusedBusId => _focusedBusId;

  /// Get or create a tracking session for a student
  Future<TrackingSession> startTracking(
    String studentId,
    String busId,
    String boardingPointId,
  ) async {
    try {
      final sessionId =
          '${studentId}_${busId}_${DateTime.now().millisecondsSinceEpoch}';

      final session = TrackingSession(
        id: sessionId,
        studentId: studentId,
        busId: busId,
        boardingPointId: boardingPointId,
        startTime: DateTime.now(),
        status: TrackingStatus.trackingToBoarding,
      );

      _activeSessions[sessionId] = session;

      // Fetch bus route if not cached
      if (!_busRoutes.containsKey(busId)) {
        await _fetchBusRoute(busId);
      }

      _focusedBusId = busId;

      // Send tracking start event to backend
      try {
        await ApiService.post('/tracking/sessions', session.toJson());
      } catch (e) {
        debugPrint('Error sending tracking session to backend: $e');
      }

      // Start polling for updates
      _startPolling();

      debugPrint('Started tracking session: $sessionId');
      notifyListeners();

      return session;
    } catch (e) {
      debugPrint('Error starting tracking: $e');
      rethrow;
    }
  }

  /// Stop tracking session
  Future<void> stopTracking(String sessionId) async {
    try {
      final session = _activeSessions[sessionId];
      if (session != null) {
        session.status = TrackingStatus.completed;
        session.endTime = DateTime.now();

        // Send completion to backend
        await ApiService.post('/tracking/sessions/$sessionId/complete', {
          'end_time': session.endTime?.toIso8601String(),
        });

        _activeSessions.remove(sessionId);
        debugPrint('Stopped tracking session: $sessionId');
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error stopping tracking: $e');
    }
  }

  /// Get active session by ID
  TrackingSession? getSession(String sessionId) {
    return _activeSessions[sessionId];
  }

  /// Get all active sessions for a student
  List<TrackingSession> getSessionsForStudent(String studentId) {
    return _activeSessions.values
        .where((s) => s.studentId == studentId && s.isActive())
        .toList();
  }

  /// Get all active sessions for a bus
  List<TrackingSession> getSessionsForBus(String busId) {
    return _activeSessions.values
        .where((s) => s.busId == busId && s.isActive())
        .toList();
  }

  /// Pin a bus for tracking - this ensures the session "opens" correctly
  Future<void> pinBus(
      String studentId, String busId, String boardingPointId) async {
    _pinnedBusIds.add(busId);

    // Check if a session already exists, if not start one
    final existingSessions = getSessionsForStudent(studentId);
    final alreadyTracking = existingSessions.any((s) => s.busId == busId);

    if (!alreadyTracking) {
      await startTracking(studentId, busId, boardingPointId);
    }

    _focusedBusId = busId;
    notifyListeners();
  }

  /// Change the boarding point (stop) for an active session
  Future<void> changeStop(String sessionId, String newBoardingPointId) async {
    final session = _activeSessions[sessionId];
    if (session == null) return;

    try {
      // Fix: Create new session instance since boardingPointId is final
      final updatedSession = TrackingSession(
        id: session.id,
        studentId: session.studentId,
        busId: session.busId,
        boardingPointId: newBoardingPointId,
        startTime: session.startTime,
        status: session.status,
      );

      // Copy metrics across
      updatedSession.distanceToBus = session.distanceToBus;
      updatedSession.totalDistanceToCollege = session.totalDistanceToCollege;
      updatedSession.estimatedMinutesToBus = session.estimatedMinutesToBus;
      updatedSession.estimatedMinutesToCollege =
          session.estimatedMinutesToCollege;

      _activeSessions[sessionId] = updatedSession;

      // Update backend
      await ApiService.put('/tracking/sessions/$sessionId', {
        'boarding_point_id': newBoardingPointId,
      });

      // Immediately recalculate distances
      await _updateTrackingSessions();

      notifyListeners();
      debugPrint('Changed stop for session $sessionId to $newBoardingPointId');
    } catch (e) {
      debugPrint('Error changing stop: $e');
    }
  }

  /// Find a boarding point across all cached routes to help markers find coordinates
  Map<String, double>? getBoardingPointLocation(String boardingPointId) {
    for (var route in _busRoutes.values) {
      try {
        final bp = route.boardingPoints.firstWhere(
          (b) => b.id.toString() == boardingPointId.toString(),
        );
        return {
          'latitude': bp.latitude,
          'longitude': bp.longitude,
        };
      } catch (e) {
        // Not found in this specific route, continue searching
        continue;
      }
    }
    return null;
  }

  /// Get latest location for an entity (bus or student)
  LiveLocation? getLatestLocation(String entityId) {
    return _latestLocations[entityId];
  }

  /// Update latest location
  void updateLatestLocation(LiveLocation location) {
    _latestLocations[location.entityId] = location;
    notifyListeners();
  }

  /// Fetch bus route from backend
  Future<void> _fetchBusRoute(String busId) async {
    try {
      final response = await ApiService.get('/tracking/routes/$busId');

      _busRoutes[busId] = BusRoute.fromJson(response);
      debugPrint('Fetched route for bus: $busId');
    } catch (e) {
      debugPrint('Error fetching bus route: $e');
    }
  }

  /// Update tracking session with current locations
  Future<void> _updateTrackingSessions() async {
    try {
      for (var session in _activeSessions.values) {
        if (!session.isActive()) continue;

        // Get current bus location
        final busLocation = _latestLocations[session.busId];
        if (busLocation == null) continue;

        // Get boarding point
        final busRoute = _busRoutes[session.busId];
        if (busRoute == null) continue;

        final boardingPoint = busRoute.boardingPoints.firstWhere(
          // Ensure ID comparison is robust (handles string vs int)
          (bp) => bp.id.toString() == session.boardingPointId.toString(),
          orElse: () => busRoute.boardingPoints.first,
        );

        // Calculate distances
        final distanceToBus = await dist.DistanceCalculator.getDistance(
          boardingPoint.latitude,
          boardingPoint.longitude,
          busLocation.latitude,
          busLocation.longitude,
        );

        final distanceToCollege = await dist.DistanceCalculator.getDistance(
          busLocation.latitude,
          busLocation.longitude,
          AppConfig.collegeLatitude,
          AppConfig.collegeLongitude,
        );

        final durationToBus = await dist.DistanceCalculator.getDuration(
          boardingPoint.latitude,
          boardingPoint.longitude,
          busLocation.latitude,
          busLocation.longitude,
        );

        final durationToCollege = await dist.DistanceCalculator.getDuration(
          busLocation.latitude,
          busLocation.longitude,
          AppConfig.collegeLatitude,
          AppConfig.collegeLongitude,
        );

        // Update session
        session.distanceToBus = distanceToBus;
        session.totalDistanceToCollege = distanceToCollege;
        session.estimatedMinutesToBus = durationToBus;
        session.estimatedMinutesToCollege = durationToCollege;

        // Update status based on distance
        if (distanceToBus < 0.2) {
          // Within 200 meters
          if (session.status == TrackingStatus.trackingToBoarding) {
            session.status = TrackingStatus.atBoarding;
            _notifySessionStatusChange(
                session, 'Bus arriving at boarding point');
          }
        } else if (distanceToCollege < 0.2) {
          if (session.status != TrackingStatus.trackingToCollege) {
            session.status = TrackingStatus.trackingToCollege;
            _notifySessionStatusChange(
                session, 'Bus left boarding point, heading to college');
          }
        }

        // Update backend with session changes
        try {
          await ApiService.put('/tracking/sessions/${session.id}', {
            'status': session.status.name,
            'distance_to_bus': session.distanceToBus,
            'total_distance_to_college': session.totalDistanceToCollege,
            'estimated_minutes_to_bus': session.estimatedMinutesToBus,
            'estimated_minutes_to_college': session.estimatedMinutesToCollege,
          });
        } catch (e) {
          debugPrint('Error updating session on backend: $e');
        }

        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error updating tracking sessions: $e');
    }
  }

  /// Notify status changes
  void _notifySessionStatusChange(TrackingSession session, String message) {
    debugPrint('Session ${session.id} status changed: $message');
    // This will trigger notifications in the UI layer
  }

  /// Start polling for bus location updates
  void _startPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(_pollingInterval, (_) async {
      await _updateTrackingSessions();
    });
  }

  /// Stop polling
  void _stopPolling() {
    _pollingTimer?.cancel();
  }

  /// Get tracking stats for a bus
  Future<Map<String, dynamic>> getTrackingStats(String busId) async {
    try {
      final sessionsForBus = getSessionsForBus(busId);

      return {
        'active_students': sessionsForBus.length,
        'students_at_boarding': sessionsForBus
            .where((s) => s.status == TrackingStatus.atBoarding)
            .length,
        'students_tracking_to_boarding': sessionsForBus
            .where((s) => s.status == TrackingStatus.trackingToBoarding)
            .length,
        'students_tracking_to_college': sessionsForBus
            .where((s) => s.status == TrackingStatus.trackingToCollege)
            .length,
        'boarding_points': _busRoutes[busId]?.boardingPoints.length ?? 0,
      };
    } catch (e) {
      debugPrint('Error getting tracking stats: $e');
      return {};
    }
  }

  /// Export tracking data to backend for analytics
  Future<void> syncTrackingData() async {
    try {
      final sessionsData =
          _activeSessions.values.map((s) => s.toJson()).toList();

      if (sessionsData.isNotEmpty) {
        await ApiService.post('/tracking/sync', {
          'sessions': sessionsData,
          'timestamp': DateTime.now().toIso8601String(),
        });
        debugPrint('Tracking data synced to backend');
      }
    } catch (e) {
      debugPrint('Error syncing tracking data: $e');
    }
  }

  @override
  void dispose() {
    _stopPolling();
    for (var sub in _updateSubscriptions.values) {
      sub.cancel();
    }
    super.dispose();
  }
}
