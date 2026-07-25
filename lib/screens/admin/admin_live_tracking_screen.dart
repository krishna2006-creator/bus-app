import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:agni_college_bus_tracker/services/location_service.dart';
import 'package:agni_college_bus_tracker/services/auth_service.dart';
import 'package:agni_college_bus_tracker/config/app_config.dart';

/// Admin Live Bus Tracking Screen using flutter_map
/// Real-time visualization of all buses and student locations
class AdminLiveTrackingScreen extends StatefulWidget {
  const AdminLiveTrackingScreen({super.key});

  @override
  State<AdminLiveTrackingScreen> createState() =>
      _AdminLiveTrackingScreenState();
}

class _AdminLiveTrackingScreenState extends State<AdminLiveTrackingScreen> {
  final MapController _mapController = MapController();
  final bool _mapReady = false;
  List<Marker> _allMarkers = [];
  int _visibleBusCount = 0;
  String _lastUpdateTime = 'Updating...';
  bool _isAutoRefresh = true;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _startAutoRefresh();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    try {
      _mapController.dispose();
    } catch (e) {
      debugPrint('Error disposing mapController: $e');
    }
    super.dispose();
  }

  void _startAutoRefresh() {
    _refreshTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (mounted && _isAutoRefresh) {
        _updateMapElements();
      }
    });
  }

  Future<void> _updateMapElements() async {
    if (!mounted) return;

    final locationService = context.read<LocationService>();
    final allLocations = locationService.allLocations.values.toList();

    List<Marker> markers = [];

    // Add all bus/location markers
    for (final loc in allLocations) {
      final isBus = loc.userType.toString().contains('driver');
      markers.add(
        Marker(
          point: LatLng(loc.latitude, loc.longitude),
          child: Tooltip(
            message:
                'Bus #${loc.busNumber}\nSpeed: ${loc.speed.toStringAsFixed(1)} km/h',
            child: Container(
              decoration: BoxDecoration(
                color: isBus ? Colors.orange : Colors.blue,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withAlpha(100),
                    blurRadius: 5,
                  )
                ],
              ),
              child: Icon(
                isBus ? Icons.directions_bus : Icons.person,
                color: Colors.white,
                size: 28,
              ),
            ),
          ),
        ),
      );
    }

    if (mounted) {
      setState(() {
        _allMarkers = markers;
        _visibleBusCount = allLocations.length;
        _lastUpdateTime =
            DateTime.now().toString().split('.')[0]; // Show time without ms
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final authService = context.watch<AuthService>();
    if (authService.currentUser == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.go('/login');
      });
      return const Center(child: CircularProgressIndicator());
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Live Bus Tracking'),
        backgroundColor: Colors.deepOrange,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        actions: [
          IconButton(
            icon: Icon(_isAutoRefresh ? Icons.pause : Icons.play_arrow),
            onPressed: () {
              setState(() {
                _isAutoRefresh = !_isAutoRefresh;
              });
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              if (_mapReady) _updateMapElements();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Map
          Expanded(
            flex: 4,
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: LatLng(
                  AppConfig.collegeLatitude,
                  AppConfig.collegeLongitude,
                ),
                initialZoom: AppConfig.defaultZoom,
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.busappvictory.app',
                ),
                MarkerLayer(markers: _allMarkers),
              ],
            ),
          ),
          // Status bar
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.deepOrange.withAlpha(230),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(26),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                )
              ],
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withAlpha(200),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.directions_bus,
                    color: Colors.deepOrange,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Buses Tracked: $_visibleBusCount / 32',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                      Text(
                        'Last update: $_lastUpdateTime',
                        style: TextStyle(
                          color: Colors.white.withAlpha(200),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                if (_isAutoRefresh)
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: Colors.green,
                      shape: BoxShape.circle,
                    ),
                  )
                else
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: Colors.grey,
                      shape: BoxShape.circle,
                    ),
                  ),
              ],
            ),
          ),
          // Bus list
          Expanded(
            flex: 2,
            child: Container(
              color: Colors.grey.shade100,
              child: Consumer<LocationService>(
                builder: (context, locationService, _) {
                  final buses = locationService.allLocations.values.toList();
                  if (buses.isEmpty) {
                    return const Center(
                      child: Text('No buses online'),
                    );
                  }
                  return ListView.builder(
                    itemCount: buses.length,
                    itemBuilder: (context, index) {
                      final bus = buses[index];
                      return ListTile(
                        leading: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: Colors.deepOrange,
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Text(
                              bus.busNumber,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                        title: Text('Bus #${bus.busNumber}'),
                        subtitle: Text(
                          '${bus.latitude.toStringAsFixed(4)}, ${bus.longitude.toStringAsFixed(4)}',
                          style: const TextStyle(fontSize: 12),
                        ),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              '${bus.speed.toStringAsFixed(1)} km/h',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                            Text(
                              bus.timestamp.toString().split('.')[0],
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
