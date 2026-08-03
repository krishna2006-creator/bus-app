import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:agni_college_bus_tracker/models/prediction_models.dart';
import 'package:agni_college_bus_tracker/models/bus_location.dart';
import 'package:agni_college_bus_tracker/models/user.dart';
import 'package:agni_college_bus_tracker/services/api_service.dart';
import 'package:agni_college_bus_tracker/services/live_tracking_service.dart';

class StopPredictionProvider with ChangeNotifier {
  LiveTrackingService? _liveTrackingService;

  void setLiveTrackingService(LiveTrackingService service) {
    _liveTrackingService = service;
  }

  BusStop? _selectedStop;
  BusStop? _previewStop;
  List<PredictionResponse> _predictions = [];
  PredictionResponse? _prediction;
  BusLocation? _liveBusLocation;
  List<BusStop> _searchResults = [];
  List<BusStop> _allStops = [];
  bool _isLoading = false;
  String? _error;
  bool _isFollowingBus = true;

  // Live tracking data (admin-style)
  double _busDistanceKm = 0.0;
  double _busSpeedKmh = 0.0;
  int _busEtaMinutes = 0;
  String _busStatus = 'Waiting for bus...';
  bool _isBusLive = false;

  WebSocketChannel? _channel;
  Timer? _reconnectTimer;
  Timer? _predictionPollTimer;
  static const _pollInterval = Duration(seconds: 10);

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

  // Live tracking getters
  double get busDistanceKm => _busDistanceKm;
  double get busSpeedKmh => _busSpeedKmh;
  int get busEtaMinutes => _busEtaMinutes;
  String get busStatus => _busStatus;
  bool get isBusLive => _isBusLive;

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

  void init() {
    _requestLocationPermission();
    _loadAllStops();
    _loadUserBoardingStop();
    _connectWebSocket();
  }

  Future<void> initAsync() async {
    await _requestLocationPermission();
    await _loadAllStops();
    await _loadUserBoardingStop();
    await _connectWebSocketAsync();
  }

  Future<void> _loadAllStops() async {
    _isLoading = true;
    _error = null;
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
        _searchResults = List.from(_allStops);
      } else {
        _error = "Failed to load stops: ${response.statusCode}";
        _searchResults = [];
      }
    } catch (e) {
      debugPrint("Error loading stops: $e");
      _error = "Failed to load boarding points";
      _searchResults = [];
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> _loadUserBoardingStop() async {
    // 1. First try local persisted selection (survives app restarts)
    final prefs = await SharedPreferences.getInstance();
    final savedLat = prefs.getDouble('boarding_lat');
    final savedLng = prefs.getDouble('boarding_lng');
    final savedName = prefs.getString('boarding_name');

    if (savedLat != null && savedLng != null) {
      _selectedStop = BusStop(
        id: prefs.getInt('boarding_id') ?? 0,
        name: savedName ?? 'Selected Stop',
        location: LatLng(savedLat, savedLng),
      );
      if (_selectedStop != null) {
        await _fetchPredictionsForStop(_selectedStop!.id);
        _startPredictionPolling(_selectedStop!.id);
      }
      notifyListeners();
      return;
    }

    // 2. Fallback: try backend
    try {
      final boardingPoint = await ApiService.getBoardingPoint();
      if (boardingPoint != null && boardingPoint['latitude'] != null && boardingPoint['longitude'] != null) {
        _selectedStop = BusStop(
          id: boardingPoint['id'] ?? 0,
          name: boardingPoint['name'] ?? 'Selected Stop',
          location: LatLng(
            double.parse(boardingPoint['latitude'].toString()),
            double.parse(boardingPoint['longitude'].toString()),
          ),
        );
        if (_selectedStop != null) {
          await _persistSelection(_selectedStop!);
          await _fetchPredictionsForStop(_selectedStop!.id);
          _startPredictionPolling(_selectedStop!.id);
        }
        notifyListeners();
      }
    } catch (e) {
      debugPrint("Error loading user boarding stop: $e");
    }
  }

  Future<void> _persistSelection(BusStop stop) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('boarding_lat', stop.location.latitude);
    await prefs.setDouble('boarding_lng', stop.location.longitude);
    await prefs.setString('boarding_name', stop.name);
    await prefs.setInt('boarding_id', stop.id);
  }

  Future<void> _requestLocationPermission() async {
    try {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        await Geolocator.requestPermission();
      }
    } catch (e) {
      debugPrint("Error requesting location permission: $e");
    }
  }

  void toggleFollowBus() {
    _isFollowingBus = !_isFollowingBus;
    notifyListeners();
  }

  Future<void> stopTracking() async {
    _predictionPollTimer?.cancel();
    _channel?.sink.close();
    _channel = null;
    _reconnectTimer?.cancel();

    _selectedStop = null;
    _previewStop = null;
    _predictions = [];
    _prediction = null;
    _liveBusLocation = null;
    _searchResults = List.from(_allStops);
    _error = null;
    _isFollowingBus = true;
    _isBusLive = false;
    _busDistanceKm = 0;
    _busSpeedKmh = 0;
    _busEtaMinutes = 0;
    _busStatus = 'Waiting for bus...';

    // Clear persisted selection
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('boarding_lat');
    await prefs.remove('boarding_lng');
    await prefs.remove('boarding_name');
    await prefs.remove('boarding_id');

    try {
      await ApiService.post('/tracking/stop', {});
    } catch (e) {
      debugPrint('Error notifying backend of tracking stop: $e');
    }

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
              // Update live tracking data from prediction
              _busDistanceKm = _prediction?.distanceKm ?? 0;
              _busEtaMinutes = _prediction?.etaMinutes ?? 0;
              _busStatus = _prediction?.status ?? 'Approaching';
              _isBusLive = true;
              notifyListeners();
            } else if (data['type'] == 'LOCATION_UPDATE') {
              final loc = data['payload'] ?? data['data'] ?? data;
              final incomingBusId = (loc['bus_id'] ?? loc['id'] ?? '').toString();

              bool isRelevant = false;
              if (_prediction != null && _prediction!.busId.toString() == incomingBusId) {
                isRelevant = true;
              } else if (_predictions.any((p) => p.busId.toString() == incomingBusId)) {
                isRelevant = true;
              }

              if (!isRelevant && _predictions.isNotEmpty) {
                return;
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

              // Update live tracking data
              _busSpeedKmh = _liveBusLocation!.speed;
              _isBusLive = true;

              // Calculate distance from bus to selected stop
              if (_selectedStop != null) {
                _busDistanceKm = _calculateDistance(
                  _liveBusLocation!.latitude,
                  _liveBusLocation!.longitude,
                  _selectedStop!.location.latitude,
                  _selectedStop!.location.longitude,
                );
                _busEtaMinutes = _busSpeedKmh > 5
                    ? ((_busDistanceKm / _busSpeedKmh) * 60).round()
                    : 0;
                _busStatus = _busDistanceKm < 0.25
                    ? 'Bus Arriving'
                    : 'Bus Approaching';
              }

              notifyListeners();
            }
          } catch (e) {
            debugPrint('Error processing WebSocket message: $e');
          }
        },
        onDone: () {
          debugPrint('WebSocket closed, attempting reconnection...');
          _scheduleReconnect();
        },
        onError: (e) {
          debugPrint('WebSocket error: $e');
          _scheduleReconnect();
        },
      );
    } catch (e) {
      debugPrint('Error connecting WebSocket: $e');
      _scheduleReconnect();
    }
  }

  double _calculateDistance(double lat1, double lng1, double lat2, double lng2) {
    const R = 6371.0; // Earth radius in km
    final dLat = _degToRad(lat2 - lat1);
    final dLng = _degToRad(lng2 - lng1);
    final a = _sin2(dLat / 2) +
        _cos(lat1) * _cos(lat2) * _sin2(dLng / 2);
    final c = 2 * _atan2(_sqrt(a), _sqrt(1 - a));
    return R * c;
  }

  double _degToRad(double deg) => deg * 3.141592653589793 / 180.0;
  double _sin2(double x) => _sin(x) * _sin(x);
  double _sin(double x) => x - (x * x * x) / 6 + (x * x * x * x * x) / 120;
  double _cos(double x) => 1 - (x * x) / 2 + (x * x * x * x) / 24;
  double _sqrt(double x) => x < 0 ? 0 : x * 0.5 + x / (x * 0.5 + 1);
  double _atan2(double y, double x) {
    if (x > 0) return _atan(y / x);
    if (x < 0 && y >= 0) return _atan(y / x) + 3.141592653589793;
    if (x < 0 && y < 0) return _atan(y / x) - 3.141592653589793;
    if (x == 0 && y > 0) return 3.141592653589793 / 2;
    if (x == 0 && y < 0) return -3.141592653589793 / 2;
    return 0;
  }
  double _atan(double x) => x - (x * x * x) / 3 + (x * x * x * x * x) / 5;

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
      final localResults = _allStops.where((stop) {
        return stop.name.toLowerCase().contains(trimmedQuery.toLowerCase());
      }).toList();

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
              id: -1,
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

  Future<void> searchByLocation(LatLng location) async {
    // Only ONE preview at a time - clear any existing preview first
    _previewStop = BusStop(
      id: -2,
      name: "Dropped Pin (${location.latitude.toStringAsFixed(4)}, ${location.longitude.toStringAsFixed(4)})",
      location: location,
    );
    notifyListeners();
  }

  void setPreviewStop(BusStop? stop) {
    _previewStop = stop;
    notifyListeners();
  }

  Future<void> selectStop(BusStop stop) async {
    final targetStop = stop;
    debugPrint("User selected boarding point: ${targetStop.name} at ${targetStop.location.latitude}, ${targetStop.location.longitude}");

    _error = null;
    _isLoading = true;
    notifyListeners();

    try {
      bool success;
      if (stop.id < 0) {
        success = await ApiService.setBoardingPointByCoordinates(targetStop.location.latitude, targetStop.location.longitude);
      } else {
        success = await ApiService.updateUserBoardingStop(targetStop.id);
      }

      if (success) {
        _error = null;
        _selectedStop = targetStop;
        _previewStop = null;
        _searchResults = [];
        // Persist locally so it survives app restarts
        await _persistSelection(targetStop);
        await _fetchPredictionsForStop(targetStop.id);
        _startPredictionPolling(targetStop.id);

        if (_prediction != null && _liveTrackingService != null) {
          await _liveTrackingService!.pinBus(
            "me",
            _prediction!.busId.toString(),
            targetStop.id.toString(),
          );
        }
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

  void clearSelection() {
    _predictionPollTimer?.cancel();
    _selectedStop = null;
    _previewStop = null;
    _predictions = [];
    _prediction = null;
    _searchResults = List.from(_allStops);
    _liveBusLocation = null;
    _error = null;
    _isBusLive = false;
    _busDistanceKm = 0;
    _busSpeedKmh = 0;
    _busEtaMinutes = 0;
    _busStatus = 'Waiting for bus...';
    notifyListeners();
  }

  Future<void> refreshPredictions() async {
    if (_selectedStop == null) return;
    await _fetchPredictionsForStop(_selectedStop!.id);
  }

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

  Future<void> _fetchPredictionsForStop(int stopId) async {
    _isLoading = true;
    notifyListeners();

    try {
      final headers = await ApiService.getHeaders();
      final response = await http.get(
        Uri.parse('${ApiService.baseUrl}/predictions?stop_id=$stopId'),
        headers: headers,
      );

      if (response.statusCode == 200 && response.body.isNotEmpty) {
        final List<dynamic> data = json.decode(response.body);
        var allPredictions = data
            .map((json) => PredictionResponse.fromJson(json as Map<String, dynamic>))
            .toList();

        // CRITICAL: Only track PINNED buses, not all buses
        // Get user's pinned buses from persisted storage
        final pinnedBuses = await _getPinnedBuses();

        if (pinnedBuses.isNotEmpty) {
          allPredictions = allPredictions
              .where((p) => pinnedBuses.contains(p.busNumber))
              .toList();
        }

        _predictions = allPredictions;
        _predictions.sort((a, b) => a.etaMinutes.compareTo(b.etaMinutes));

        if (_predictions.isNotEmpty) {
          _prediction = _predictions.first;
          _busDistanceKm = _prediction!.distanceKm;
          _busEtaMinutes = _prediction!.etaMinutes;
          _busStatus = _prediction!.status;
          _isBusLive = true;
        } else {
          _prediction = null;
          _isBusLive = false;
        }
      } else {
        _predictions = [];
        _prediction = null;
        _isBusLive = false;
      }
    } catch (e) {
      debugPrint("Error fetching predictions for stop $stopId: $e");
      _predictions = [];
      _prediction = null;
      _isBusLive = false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Helper to get pinned buses from SharedPreferences (persisted by AuthService)
  Future<List<String>> _getPinnedBuses() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final currentUserJson = prefs.getString('currentUser');
      if (currentUserJson != null) {
        final userData = json.decode(currentUserJson);
        final pinned = userData['pinnedBuses'];
        if (pinned is List) {
          return pinned.map((e) => e.toString()).toList();
        }
      }
    } catch (e) {
      debugPrint('Error reading pinned buses: $e');
    }
    return [];
  }
}