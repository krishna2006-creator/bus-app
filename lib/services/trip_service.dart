import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:agni_college_bus_tracker/models/trip.dart';
import 'package:agni_college_bus_tracker/services/api_service.dart';

class TripService extends ChangeNotifier {
  static const _tripsKey = 'trips';
  List<Trip> _trips = [];
  int _activeTripCount = 0;

  List<Trip> get trips => _trips;
  List<Trip> get activeTrips =>
      _trips.where((t) => t.status == TripStatus.active).toList();
  int get activeTripCount => _activeTripCount;
  Trip? get activeTrip {
    try {
      return _trips.firstWhere((t) => t.status == TripStatus.active);
    } catch (_) {
      return null;
    }
  }

  Future<void> initialize() async {
    // Try to fetch from backend first
    await _fetchFromBackend();

    // Fallback to local storage
    if (_trips.isEmpty) {
      final prefs = await SharedPreferences.getInstance();
      final tripsJson = prefs.getString(_tripsKey);
      if (tripsJson != null) {
        try {
          final List decoded = json.decode(tripsJson);
          _trips = decoded.map((e) => Trip.fromJson(e)).toList();
        } catch (e) {
          debugPrint('Error loading trips: $e');
        }
      }
    }
    notifyListeners();
  }

  Future<void> _fetchFromBackend() async {
    try {
      final statsData = await ApiService.get('/admin/stats');
      if (statsData is Map<String, dynamic>) {
        _activeTripCount = statsData['active_tracking_sessions'] ?? 0;
      }
    } catch (e) {
      debugPrint('Error fetching trip stats from backend: $e');
    }

    try {
      final busesData = await ApiService.get('/admin/buses');
      if (busesData is List) {
        _trips = busesData
            .where((b) {
              final status = b['status']?.toString().toLowerCase() ?? '';
              return status == 'active' ||
                  status == 'running' ||
                  b['active_users'] > 0;
            })
            .map((b) => Trip(
                  id: 'trip_${b['id']}',
                  busNumber: b['bus_number']?.toString() ?? b['id'].toString(),
                  driverName: b['driver_name']?.toString() ?? 'Unknown',
                  startTime: DateTime.now(),
                  status: TripStatus.active,
                ))
            .toList();
        _activeTripCount = _trips.length;
      }
    } catch (e) {
      debugPrint('Error fetching active trips from backend: $e');
    }
  }

  // Refresh active trips count from backend
  Future<void> refreshActiveTrips() async {
    await _fetchFromBackend();
    notifyListeners();
  }

  Future<void> startTrip(Trip trip) async {
    _trips.insert(0, trip);
    _activeTripCount =
        _trips.where((t) => t.status == TripStatus.active).length;
    await _saveTrips();
    notifyListeners();
  }

  Future<void> endTrip(String tripId) async {
    final index = _trips.indexWhere((t) => t.id == tripId);
    if (index != -1) {
      _trips[index] = _trips[index].copyWith(
        endTime: DateTime.now(),
        status: TripStatus.completed,
      );
      _activeTripCount =
          _trips.where((t) => t.status == TripStatus.active).length;
      await _saveTrips();
      notifyListeners();
    }
  }

  Trip? getActiveTripForBus(String busNumber) {
    try {
      return _trips.firstWhere(
        (t) => t.busNumber == busNumber && t.status == TripStatus.active,
      );
    } catch (e) {
      return null;
    }
  }

  List<Trip> getTripsForBus(String busNumber) =>
      _trips.where((t) => t.busNumber == busNumber).toList();

  Future<void> refreshFromBackend() async {
    await _fetchFromBackend();
    notifyListeners();
  }

  Future<void> _saveTrips() async {
    final prefs = await SharedPreferences.getInstance();
    final tripsJson = json.encode(_trips.map((e) => e.toJson()).toList());
    await prefs.setString(_tripsKey, tripsJson);
  }
}
