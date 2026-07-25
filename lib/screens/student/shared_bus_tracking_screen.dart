import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'dart:convert';
import 'dart:async';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:agni_college_bus_tracker/models/bus.dart';
import 'package:agni_college_bus_tracker/models/bus_location.dart'; // Keep this import
import 'package:agni_college_bus_tracker/models/user.dart';
import 'package:agni_college_bus_tracker/config/app_config.dart';
import 'package:agni_college_bus_tracker/services/api_service.dart';

/// Live Tracking Screen for Shared Bus Locations
/// Shows real-time location of buses when students are actively sharing location
class SharedBusTrackingScreen extends StatefulWidget {
  final Bus bus;

  // NOTE: The `BusLocation` model (likely in `lib/models/bus_location.dart`)
  // needs to be updated to include a `userName` field.
  //
  // Example modification for `lib/models/bus_location.dart`:
  /*
  import 'package:agni_college_bus_tracker/models/user.dart'; // Assuming UserRole is here

  class BusLocation {
    final double latitude;
    final double longitude;
    final double speed;
    final DateTime timestamp;
    final String busNumber;
    final UserRole userType;
    final String userName; // <--- ADD THIS FIELD

    BusLocation({required this.latitude, required this.longitude, required this.speed, required this.timestamp, required this.busNumber, required this.userType, this.userName = 'Unknown'});
  }
  */

  const SharedBusTrackingScreen({super.key, required this.bus});

  @override
  State<SharedBusTrackingScreen> createState() =>
      _SharedBusTrackingScreenState();
}

class _SharedBusTrackingScreenState extends State<SharedBusTrackingScreen> {
  late MapController _mapController;
  final Map<String, BusLocation> _activeLocations = {};
  final Map<String, int> _userUpdateCounts =
      {}; // Track updates per individual sender
  int _updateCount = 0;
  bool _isLive = false;
  WebSocketChannel? _channel;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    _initializeTracking();
  }

  @override
  void dispose() {
    _channel?.sink.close();
    super.dispose();
  }

  Future<void> _initializeTracking() async {
    final token = await ApiService.getToken();
    if (token == null) return;

    // Convert http://192.168.x.x:8000 to ws://192.168.x.x:8000
    final url =
        '${AppConfig.wsUrl}/api/ws/ws/location/${widget.bus.id}?token=$token';

    try {
      _channel = WebSocketChannel.connect(Uri.parse(url));
      _channel!.stream.listen((message) {
        final data = jsonDecode(message);
        final type = data['type'];
        final payload = data['payload'] ?? data['data'] ?? data;
        final senderId =
            (payload['id'] ?? payload['user_id'] ?? 'unknown').toString();
        final userName = payload['user_name']?.toString() ??
            'Unknown User'; // Extract user name

        if (type == 'LOCATION_UPDATE' || type == 'LAST_KNOWN_LOCATION') {
          setState(() {
            if ((payload['latitude'] as num?)?.toDouble() == 0.0 &&
                (payload['longitude'] as num?)?.toDouble() == 0.0) {
              _activeLocations.remove(senderId);
              _userUpdateCounts.remove(senderId);
              _isLive = _activeLocations.isNotEmpty;
              return;
            }

            final roleStr =
                payload['user_role']?.toString().toLowerCase() ?? 'driver';
            final userRole = UserRole.values.firstWhere(
              (e) => e.toString().split('.').last.toLowerCase() == roleStr,
              orElse: () => UserRole.driver,
            );

            final newLocation = BusLocation(
              latitude: (payload['latitude'] as num?)?.toDouble() ?? 0.0,
              longitude: (payload['longitude'] as num?)?.toDouble() ?? 0.0,
              speed: (payload['speed'] ?? 0.0).toDouble(),
              timestamp: DateTime.now(),
              busNumber: widget.bus.busNumber,
              userType: userRole,
              userName: userName,
            );

            _userUpdateCounts[senderId] =
                (_userUpdateCounts[senderId] ?? 0) + 1;
            _activeLocations[senderId] = newLocation;
            _updateCount++;
            _isLive = true;

            if (_updateCount == 1) {
              _mapController.move(
                LatLng(newLocation.latitude, newLocation.longitude),
                15.0,
              );
            }
          });
        } else if (type == 'LOCATION_CLEARED') {
          setState(() {
            _activeLocations.remove(senderId);
            _userUpdateCounts.remove(senderId);
            _isLive = _activeLocations.isNotEmpty;
          });
        }
      }, onError: (err) {
        debugPrint("WebSocket Error: $err");
        setState(() => _isLive = false);
        _userUpdateCounts.clear();
      }, onDone: () {
        setState(() => _isLive = false);
        _userUpdateCounts.clear();
      });
    } catch (e) {
      debugPrint("Connection failed: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Bus ${widget.bus.busNumber} - Live Tracking'),
        elevation: 0,
        actions: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Center(
              child: _isLive
                  ? Chip(
                      label: Text('Live • $_updateCount updates'),
                      backgroundColor: Colors.green,
                      labelStyle: const TextStyle(color: Colors.white),
                    )
                  : Chip(
                      label: const Text('Waiting...'),
                      backgroundColor: Colors.grey,
                      labelStyle: const TextStyle(color: Colors.white),
                    ),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          // Map
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _activeLocations.isNotEmpty
                  ? LatLng(_activeLocations.values.first.latitude,
                      _activeLocations.values.first.longitude)
                  : const LatLng(
                      AppConfig.collegeLatitude, AppConfig.collegeLongitude),
              initialZoom: 15.0,
              maxZoom: 19.0,
              minZoom: 5.0,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.busapp.victory',
              ),
              MarkerLayer(
                markers: [
                  // College marker
                  Marker(
                    width: 80,
                    height: 80,
                    point: LatLng(
                        AppConfig.collegeLatitude, AppConfig.collegeLongitude),
                    child: Tooltip(
                      message: 'College',
                      child: Icon(Icons.school, color: Colors.red, size: 32),
                    ),
                  ),

                  // Bus location marker
                  ..._activeLocations.entries.map((entry) {
                    final loc = entry.value;
                    return Marker(
                      width: 80,
                      height: 80,
                      point: LatLng(loc.latitude, loc.longitude),
                      child: Tooltip(
                        message:
                            'Bus ${widget.bus.busNumber} (${loc.userType.toString().split('.').last})',
                        child: const Icon(
                          Icons.directions_bus,
                          color: Colors.blue,
                          size: 40,
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ],
          ),

          // Info card
          Positioned(
            bottom: 20,
            left: 20,
            right: 20,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 8,
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Bus ${widget.bus.busNumber}',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (_isLive)
                        const Icon(Icons.circle, color: Colors.green, size: 12),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (_activeLocations.isNotEmpty) ...[
                    // Show stats for the first active location (usually the driver)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Speed',
                              style:
                                  TextStyle(fontSize: 12, color: Colors.grey),
                            ),
                            Text(
                              '${_activeLocations.values.first.speed.toStringAsFixed(1)} km/h',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Updates',
                              style:
                                  TextStyle(fontSize: 12, color: Colors.grey),
                            ),
                            Text(
                              '$_updateCount',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ] else ...[
                    const Text(
                      'Waiting for location updates...',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
