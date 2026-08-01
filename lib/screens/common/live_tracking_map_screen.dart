import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:agni_college_bus_tracker/services/location_service.dart';
import 'package:agni_college_bus_tracker/services/auth_service.dart';
import 'package:agni_college_bus_tracker/services/pinned_bus_monitor_service.dart';
import 'package:agni_college_bus_tracker/services/api_service.dart';
import 'package:agni_college_bus_tracker/config/app_config.dart';
import 'package:agni_college_bus_tracker/models/bus.dart';
import 'package:agni_college_bus_tracker/models/bus_location.dart';
import 'package:agni_college_bus_tracker/models/user.dart';

/// Live Bus Tracking Screen for Students, Staff, and Drivers
/// Real-time visualization of buses on the map
class LiveTrackingMapScreen extends StatefulWidget {
  final Bus? bus;
  final bool showOnlyPinnedBuses;

  const LiveTrackingMapScreen({
    super.key,
    this.bus,
    this.showOnlyPinnedBuses = false,
  });

  @override
  State<LiveTrackingMapScreen> createState() => _LiveTrackingMapScreenState();
}

class _LiveTrackingMapScreenState extends State<LiveTrackingMapScreen> {
  final MapController _mapController = MapController();
  Timer? _refreshTimer;
  List<Marker> _allMarkers = [];
  int _visibleBusCount = 0;
  String _lastUpdateTime = 'Updating...';
  bool _isAutoRefresh = true;
  LatLng _userLocation = const LatLng(AppConfig.collegeLatitude, AppConfig.collegeLongitude);

  @override
  void initState() {
    super.initState();
    _startAutoRefresh();
    _getUserLocation();
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

  Future<void> _getUserLocation() async {
    try {
      final authService = context.read<AuthService>();
      final user = authService.currentUser;
      
      if (user != null) {
        // Try to get user's boarding stop location
        final headers = await ApiService.getHeaders();
        final response = await http.get(
          Uri.parse('${ApiService.baseUrl}/stops/${user.boardingStopId}'),
          headers: headers,
        );
        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          _userLocation = LatLng(
            (data['latitude'] as num).toDouble(),
            (data['longitude'] as num).toDouble(),
          );
        }
      }
    } catch (e) {
      debugPrint('Error getting user location: $e');
    }
  }

  void _startAutoRefresh() {
    _refreshTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _isAutoRefresh) {
        _updateMapElements();
      }
    });
  }

  Future<void> _updateMapElements() async {
    if (!mounted) return;

    final locationService = context.read<LocationService>();
    final authService = context.read<AuthService>();
    final pinnedBusMonitor = context.read<PinnedBusMonitorService>();
    
    final user = authService.currentUser;
    if (user == null) return;

    List<BusLocation> locationsToShow = [];
    
    if (widget.showOnlyPinnedBuses && user.pinnedBuses.isNotEmpty) {
      // Show only pinned buses
      final allLocations = locationService.allLocations.values.toList();
      locationsToShow = allLocations.where((loc) => user.pinnedBuses.contains(loc.busNumber)).toList();
    } else if (widget.bus != null) {
      // Show specific bus
      final allLocations = locationService.allLocations.values.toList();
      locationsToShow = allLocations.where((loc) => loc.busNumber == widget.bus!.busNumber).toList();
    } else {
      // Show all available locations
      locationsToShow = locationService.allLocations.values.toList();
    }

    List<Marker> markers = [];

    // Add college marker
    markers.add(
      Marker(
        point: const LatLng(AppConfig.collegeLatitude, AppConfig.collegeLongitude),
        child: Tooltip(
          message: 'College Location',
          child: Container(
            decoration: BoxDecoration(
              color: Colors.red,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(100),
                  blurRadius: 5,
                )
              ],
            ),
            child: const Icon(
              Icons.school,
              color: Colors.white,
              size: 32,
            ),
          ),
        ),
      ),
    );

    // Add user's boarding point marker
    if (_userLocation != const LatLng(AppConfig.collegeLatitude, AppConfig.collegeLongitude)) {
      markers.add(
        Marker(
          point: _userLocation,
          child: Tooltip(
            message: 'Your Boarding Point',
            child: Container(
              decoration: BoxDecoration(
                color: Colors.green,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withAlpha(100),
                    blurRadius: 5,
                  )
                ],
              ),
              child: const Icon(
                Icons.location_on,
                color: Colors.white,
                size: 28,
              ),
            ),
          ),
        ),
      );
    }

    // Add bus markers
    for (final loc in locationsToShow) {
      final isPinned = user.pinnedBuses.contains(loc.busNumber);
      final trackingData = pinnedBusMonitor.trackingData[loc.busNumber];
      
      markers.add(
        Marker(
          point: LatLng(loc.latitude, loc.longitude),
          child: Tooltip(
            message: _getBusTooltip(loc, trackingData),
            child: Container(
              decoration: BoxDecoration(
                color: isPinned ? Colors.green : Colors.orange,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withAlpha(100),
                    blurRadius: 5,
                  )
                ],
              ),
              child: Icon(
                Icons.directions_bus,
                color: Colors.white,
                size: isPinned ? 32 : 28,
              ),
            ),
          ),
        ),
      );
    }

    if (mounted) {
      setState(() {
        _allMarkers = markers;
        _visibleBusCount = locationsToShow.length;
        _lastUpdateTime = DateTime.now().toString().split('.')[0];
      });
    }
  }

  String _getBusTooltip(BusLocation loc, PinnedBusTrackingData? trackingData) {
    String tooltip = 'Bus #${loc.busNumber}\n';
    tooltip += 'Speed: ${loc.speed.toStringAsFixed(1)} km/h\n';
    
    if (trackingData != null) {
      tooltip += 'Status: ${trackingData.statusLabel}\n';
      tooltip += 'Distance: ${trackingData.distanceKm.toStringAsFixed(2)} km\n';
      tooltip += 'ETA: ${trackingData.etaMinutes} min\n';
    }
    
    tooltip += 'Updated: ${loc.timestamp.toString().split('.')[0]}';
    return tooltip;
  }

  @override
  Widget build(BuildContext context) {
    final authService = context.watch<AuthService>();
    final pinnedBusMonitor = context.watch<PinnedBusMonitorService>();
    
    if (authService.currentUser == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.go('/login');
      });
      return const Center(child: CircularProgressIndicator());
    }

    final user = authService.currentUser!;
    final trackingData = pinnedBusMonitor.trackingData;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.bus != null 
            ? 'Track Bus #${widget.bus!.busNumber}' 
            : 'Live Bus Tracking'),
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
              _updateMapElements();
            },
          ),
          if (user.role == UserRole.student || user.role == UserRole.staff)
            IconButton(
              icon: Icon(widget.showOnlyPinnedBuses ? Icons.push_pin : Icons.map),
              onPressed: () {
                if (user.pinnedBuses.isNotEmpty) {
                  context.go('/student/pinned-buses', extra: [widget.bus]);
                }
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
                initialCenter: _userLocation,
                initialZoom: AppConfig.trackingZoom,
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
                        'Buses Tracked: $_visibleBusCount',
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
          // Pinned bus status (for students/staff)
          if (user.pinnedBuses.isNotEmpty && widget.bus == null)
            Expanded(
              flex: 2,
              child: Container(
                color: Colors.grey.shade100,
                child: ListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: user.pinnedBuses.length,
                  itemBuilder: (context, index) {
                    final busNumber = user.pinnedBuses[index];
                    final data = trackingData[busNumber];
                    
                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      child: ListTile(
                        leading: Container(
                          width: 40,
                          height: 40,
                          decoration: const BoxDecoration(
                            color: Colors.green,
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Text(
                              busNumber,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ),
                        title: Text('Bus #$busNumber'),
                        subtitle: data != null
                            ? Text('${data.statusLabel} • ${data.distanceKm.toStringAsFixed(2)} km away')
                            : const Text('Waiting for location...'),
                        trailing: data != null
                            ? Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    '${data.etaMinutes} min',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                      color: Colors.deepOrange,
                                    ),
                                  ),
                                ],
                              )
                            : null,
                      ),
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