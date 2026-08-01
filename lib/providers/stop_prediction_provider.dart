import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:agni_college_bus_tracker/models/prediction_models.dart';
import 'package:agni_college_bus_tracker/models/bus_location.dart';
import 'package:agni_college_bus_tracker/models/user.dart';
import 'package:agni_college_bus_tracker/services/api_service.dart';
import 'package:agni_college_bus_tracker/services/live_tracking_service.dart';

class StopPredictionProvider with ChangeNotifier {
  LiveTrackingService? _liveTrackingService;

  /// Inject tracking service to sync pinning with live tracking UI
  void setLiveTrackingService(LiveTrackingService service) {
    _liveTrackingService = service;
  }

  // State
  BusStop? _selectedStop;
  BusStop? _previewStop;
  List<PredictionResponse> _predictions = [];
  PredictionResponse? _prediction; // Keep for backward compatibility
  BusLocation? _liveBusLocation;
  List<BusStop> _searchResults = [];
  List<BusStop> _allStops = []; // Add all stops
  bool _isLoading = false;
  String? _error;
  bool _isFollowingBus = true; // Default to enabled

  // WebSocket
  WebSocketChannel? _channel;
  Timer? _reconnectTimer;

  /// Polling fallback timer for predictions - keeps predictions fresh
  /// when the WebSocket endpoint is unavailable
  Timer? _predictionPollTimer;
  static const _pollInterval = Duration(seconds: 5);

  // Getters
  BusStop? get selectedStop => _selectedStop;
  BusStop? get previewStop => _previewStop;
  List<PredictionResponse> get predictions => _predictions;
  PredictionResponse? get prediction => _prediction;
  BusLocation? get liveBusLocation => _liveBusLocation;
  List<BusStop> get searchResults => _searchResults;
  List<BusStop> get allStops => _allStops;
  bool get isLoading => _isLoading;
  bool get isFollowingBus => _isFollowingBus;
  String? get error => _error;

  Future<String> _getWsUrl() async {
    final baseUrl = ApiService.baseUrl;
    final token = await ApiService.getToken();
    final wsBase = baseUrl.startsWith('https')
        ? baseUrl.replaceFirst('https', 'wss')
        : baseUrl.replaceFirst('http', 'ws');
    return token != null
        ? '$wsBase/ws/stop-prediction-live?token=$token'
        : '$wsBase/ws/stop-prediction-live';
  }

  // --- Initialization ---
  void init() {
    _requestLocationPermission();
    _loadAllStops(); // Load all stops upfront
    _loadUserBoardingStop(); // Load existing boarding stop
    _connectWebSocket();
  }

  // Async init for compatibility with token loading
  Future<void> initAsync() async {
    await _requestLocationPermission();
    await _loadAllStops(); // Load all stops upfront
    await _loadUserBoardingStop();
    await _connectWebSocketAsync();
  }

  /// Load all available stops
  Future<void> _loadAllStops() async {
    _isLoading = true;
    notifyListeners();
    try {
      final headers = await ApiService.getHeaders();
      final response = await http.get(
        Uri.parse('${ApiService.baseUrl}/stops'),
        headers: headers,
      );
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        _allStops = data.map((json) => BusStop.fromJson(json)).toList();
        _searchResults = _allStops; // Show all by default
      } else {
        _error = "Failed to load stops: ${response.statusCode}";
      }
    } catch (e) {
      debugPrint("Error loading stops: $e");
      _error = "Failed to load boarding points";
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Load the user's currently selected boarding stop from the backend
  Future<void> _loadUserBoardingStop() async {
    try {
      final headers = await ApiService.getHeaders();
      final response = await http.get(
        Uri.parse('${ApiService.baseUrl}/students/me/boarding_stop'),
        headers: headers,
      );

      if (response.statusCode == 200 &&
          response.body.isNotEmpty &&
          response.body.trim() != 'null') {
        final data = json.decode(response.body);
        if (data != null) {
          _selectedStop = BusStop.fromJson(data);
          if (_selectedStop != null) {
            await _fetchPredictionsForStop(_selectedStop!.id);
            // Start polling as fallback to WebSocket
            _startPredictionPolling(_selectedStop!.id);
          }
          notifyListeners();
          return;
        }
      }

      debugPrint(
          "No boarding stop found for user or server error: ${response.statusCode}");
    } catch (e) {
      debugPrint("Error loading user boarding stop: $e");
    }
  }

  // Request location permission
  Future<void> _requestLocationPermission() async {
    try {
      final permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        _error = "Location permission required for stop prediction";
        notifyListeners();
      }
    } catch (e) {
      debugPrint("Error requesting location permission: $e");
    }
  }

  void toggleFollowBus() {
    _isFollowingBus = !_isFollowingBus;
    notifyListeners();
  }

  /// Stop tracking for the current user.
  /// When a stop location is clicked, this stops location updates for that user
  /// by clearing the selected stop, stopping polling, and notifying the backend.
  Future<void> stopTracking() async {
    _predictionPollTimer?.cancel();
    _channel?.sink.close();
    _channel = null;
    _reconnectTimer?.cancel();

    // Clear all tracking state
    _selectedStop = null;
    _previewStop = null;
    _predictions = [];
    _prediction = null;
    _liveBusLocation = null;
    _searchResults = _allStops;
    _error = null;
    _isFollowingBus = true;

    // Notify backend that tracking is stopped
    try {
      await ApiService.post('/tracking/stop', {});
    } catch (e) {
      debugPrint('Error notifying backend of tracking stop: $e');
    }

    // Stop live tracking service sessions
    try {
      _liveTrackingService?.dispose();
    } catch (e) {
      debugPrint('Error stopping live tracking service: $e');
    }

    notifyListeners();
    debugPrint('Stop tracking: cleared all tracking state');
  }

  @override
  void dispose() {
    _channel?.sink.close();
    _reconnectTimer?.cancel();
    _predictionPollTimer?.cancel();
    super.dispose();
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 5), () {
      debugPrint('Attempting WebSocket reconnection...');
      _connectWebSocket();
    });
  }

  void _connectWebSocket() {
    _channel?.sink.close();
    _connectWebSocketAsync();
  }

  Future<void> _connectWebSocketAsync() async {
    try {
      final wsUrl = await _getWsUrl();
      _channel = WebSocketChannel.connect(Uri.parse(wsUrl));
      _channel!.stream.listen(
        (message) {
          try {
            final data = json.decode(message);
            debugPrint('WebSocket Update: ${data['type']}');
            if (data['type'] == 'PREDICTION_UPDATE') {
              _prediction = PredictionResponse.fromJson(data['payload']);
              notifyListeners();
            } else if (data['type'] == 'LOCATION_UPDATE') {
              // Robust parsing for different backend payload structures
              final loc = data['payload'] ?? data['data'] ?? data;
              final incomingBusId =
                  (loc['bus_id'] ?? loc['id'] ?? '').toString();

              // Allow update if it's the specific bus we track, or if we have general predictions
              bool isRelevant = false;
              if (_prediction != null &&
                  _prediction!.busId.toString() == incomingBusId) {
                isRelevant = true;
              } else if (_predictions
                  .any((p) => p.busId.toString() == incomingBusId)) {
                isRelevant = true;
              }

              if (!isRelevant && _predictions.isNotEmpty) {
                return; // Ignore buses that aren't on our selected stop's route
              }

              _liveBusLocation = BusLocation(
                busNumber: (loc['bus_id'] ?? loc['id'] ?? '').toString(),
                latitude: (loc['latitude'] as num).toDouble(),
                longitude: (loc['longitude'] as num).toDouble(),
                speed: (loc['speed'] ?? 0.0).toDouble(),
                timestamp: DateTime.now(),
                userType: UserRole.driver,
                isSharedByStudent: false,
              );
              notifyListeners();
            }
          } catch (e) {
            debugPrint('Error processing WebSocket message: $e');
          }
        },
        onDone: () {
          debugPrint('WebSocket closed, attempting reconnection...');
          // Don't clear predictions on WS disconnect - they were loaded via REST
          _scheduleReconnect();
        },
        onError: (e) {
          debugPrint('WebSocket error: $e');
          // Don't clear predictions on WS error - they were loaded via REST
          _scheduleReconnect();
        },
      );
    } catch (e) {
      debugPrint('Error connecting WebSocket: $e');
      _scheduleReconnect();
    }
  }

  // --- API Actions ---

  Future<void> searchStops(String query) async {
    final trimmedQuery = query.trim();
    if (trimmedQuery.isEmpty) {
      _searchResults = List.from(_allStops);
      notifyListeners();
      return;
    }

    _isLoading = true;
    notifyListeners();

    try {
      // 1. Local Search (Filter existing stops)
      final localResults = _allStops.where((stop) {
        return stop.name.toLowerCase().contains(trimmedQuery.toLowerCase());
      }).toList();

      // 2. Global Search (Geocoding via Nominatim)
      List<BusStop> globalResults = [];
      if (trimmedQuery.length >= 3) {
        final url = Uri.parse(
            'https://nominatim.openstreetmap.org/search?q=${Uri.encodeComponent(trimmedQuery)}&format=json&limit=5');
        final response = await http.get(url, headers: {
          'User-Agent': 'AgniCollegeBusTracker/1.0',
        });

        if (response.statusCode == 200) {
          final List data = json.decode(response.body);
          globalResults = data.map((item) {
            return BusStop(
              id: -1, // Mark as external result
              name: item['display_name'] ?? 'Unknown',
              location: LatLng(
                double.parse(item['lat']),
                double.parse(item['lon']),
              ),
            );
          }).toList();
        }
      }

      _searchResults = [...localResults, ...globalResults];
    } catch (e) {
      debugPrint("Search error: $e");
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Select location by tapping map (Reverse Geocoding)
  Future<void> searchByLocation(LatLng location) async {
    _previewStop = BusStop(
      id: -2, // Signals a manual map pin
      name:
          "Dropped Pin (${location.latitude.toStringAsFixed(4)}, ${location.longitude.toStringAsFixed(4)})",
      location: location,
    );
    notifyListeners();
  }

  /// Update the stop currently being previewed on the map
  void setPreviewStop(BusStop? stop) {
    _previewStop = stop;
    notifyListeners();
  }

  Future<void> selectStop(BusStop stop) async {
    // REDESIGN: Allow users to choose ANY point on the map
    // No longer snapping to nearest system stop - users can pick any boarding point
    final targetStop = stop;
    debugPrint("User selected boarding point: ${targetStop.name} at ${targetStop.location.latitude}, ${targetStop.location.longitude}");

    _error = null;
    _isLoading = true;
    notifyListeners();

    try {
      final success = await ApiService.updateUserBoardingStop(targetStop.id);

      if (success) {
        _error = null;
        _selectedStop = targetStop;
        _previewStop = null;
        _searchResults = []; // Clear search
        await _fetchPredictionsForStop(targetStop.id); // Fetch predictions list

        // Start polling predictions every 5 seconds as a fallback
        // to the WebSocket (which may not be available on all backends)
        _startPredictionPolling(targetStop.id);

        // Automatically trigger live tracking session to "open" the dashboard widget
        if (_prediction != null && _liveTrackingService != null) {
          await _liveTrackingService!.pinBus(
            "me", // Student ID handled by backend session
            _prediction!.busId.toString(),
            targetStop.id.toString(),
          );
        }

        // Send notification that boarding point was selected
        await _sendBoardingPointNotification(stop);
      } else {
        _error = "Failed to update stop";
      }
    } catch (e) {
      debugPrint('Exception selecting boarding stop: $e');
      _error = "Connection error";
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Clear the selected stop and go back to search
  void clearSelection() {
    _predictionPollTimer?.cancel();
    _selectedStop = null;
    _previewStop = null;
    _predictions = [];
    _prediction = null;
    _searchResults = _allStops; // Restore all stops for searching again
    _liveBusLocation = null;
    _error = null;
    notifyListeners();
  }

  /// Refresh predictions for the currently selected stop
  Future<void> refreshPredictions() async {
    if (_selectedStop == null) return;
    await _fetchPredictionsForStop(_selectedStop!.id);
  }

  /// Start polling predictions for the selected stop every 5 seconds
  /// This serves as a fallback when the WebSocket endpoint is unavailable
  void _startPredictionPolling(int stopId) {
    _predictionPollTimer?.cancel();
    _predictionPollTimer = Timer.periodic(_pollInterval, (_) async {
      if (_selectedStop == null || _selectedStop!.id != stopId) {
        _predictionPollTimer?.cancel();
        return;
      }
      await _fetchPredictionsForStop(stopId);
    });
  }

  /// Fetch list of predictions for a specific stop
  Future<void> _fetchPredictionsForStop(int stopId) async {
    _isLoading = true;
    notifyListeners();

    try {
      final headers = await ApiService.getHeaders();
      // REDESIGN: Use new endpoint that accepts any GPS coordinates
      final response = await http.get(
        Uri.parse('${ApiService.baseUrl}/predictions?stop_id=$stopId'),
        headers: headers,
      );

      if (response.statusCode == 200 && response.body.isNotEmpty) {
        final List<dynamic> data = json.decode(response.body);
        _predictions = data
            .map((json) =>
                PredictionResponse.fromJson(json as Map<String, dynamic>))
            .toList();
        // Sort by ETA minutes
        _predictions.sort((a, b) => a.etaMinutes.compareTo(b.etaMinutes));

        // Set first as primary prediction for backward compatibility
        if (_predictions.isNotEmpty) {
          _prediction = _predictions.first;
        } else {
          _prediction = null;
        }
      } else {
        _predictions = [];
        _prediction = null;
      }
    } catch (e) {
      debugPrint("Error fetching predictions for stop $stopId: $e");
      _predictions = [];
      _prediction = null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> _sendBoardingPointNotification(BusStop stop) async {
    try {
      // This would be sent by the backend and received via NotificationService WebSocket
      // For now, we can log this event for the backend to process
      debugPrint('Student selected boarding point: ${stop.name}');
    } catch (e) {
      debugPrint('Error sending boarding point notification: $e');
    }
  }
}
