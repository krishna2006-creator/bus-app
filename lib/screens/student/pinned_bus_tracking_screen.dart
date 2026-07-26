import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:agni_college_bus_tracker/models/bus.dart';
import 'package:agni_college_bus_tracker/models/bus_location.dart';
import 'package:agni_college_bus_tracker/models/user.dart';
import 'package:agni_college_bus_tracker/config/app_config.dart';
import 'package:agni_college_bus_tracker/services/api_service.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'dart:convert' as json;

/// Live Tracking Screen for Pinned Buses Only
/// Shows real-time location of pinned buses on map
class PinnedBusTrackingScreen extends StatefulWidget {
  final List<Bus> pinnedBuses;

  const PinnedBusTrackingScreen({super.key, required this.pinnedBuses});

  @override
  State<PinnedBusTrackingScreen> createState() =>
      _PinnedBusTrackingScreenState();
}

class _PinnedBusTrackingScreenState extends State<PinnedBusTrackingScreen> {
  late MapController _mapController;
  final Map<int, BusLocation?> _busLocations = {};
  final Map<int, WebSocketChannel?> _wsChannels = {};
  final Map<int, int> _updateCounts = {};
  int? _selectedBusId;
  bool _isConnected = false;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    // Initialize update counters
    for (final bus in widget.pinnedBuses) {
      _updateCounts[bus.id] = 0;
    }
    _connectToPinnedBuses();
  }

  @override
  void dispose() {
    // Close all WebSocket connections
    for (var channel in _wsChannels.values) {
      channel?.sink.close();
    }
    super.dispose();
  }

  Future<void> _connectToPinnedBuses() async {
    if (widget.pinnedBuses.isEmpty) {
      return;
    }

    setState(() => _isConnected = false);

    // Connect to each pinned bus WebSocket room
    for (final bus in widget.pinnedBuses) {
      try {
        final wsUrl =
            '${AppConfig.wsUrl}/api/ws/location/${bus.id}?token=${await ApiService.getToken() ?? ''}';
        final channel = WebSocketChannel.connect(Uri.parse(wsUrl));

        _wsChannels[bus.id] = channel;

        channel.stream.listen(
          (message) {
            try {
              final data = json.jsonDecode(message);
              final type = data['type'];
              final locData = data['payload'] ?? data['data'] ?? data;

              if (type == 'LOCATION_UPDATE' || type == 'LAST_KNOWN_LOCATION') {
                setState(() {
                  _busLocations[bus.id] = BusLocation(
                    busNumber: bus.busNumber,
                    latitude: (locData['latitude'] as num).toDouble(),
                    longitude: (locData['longitude'] as num).toDouble(),
                    speed: (locData['speed'] ?? 0.0).toDouble(),
                    timestamp: DateTime.now(),
                    userType: UserRole.driver,
                  );
                  _updateCounts[bus.id] = (_updateCounts[bus.id] ?? 0) + 1;

                  // Auto-focus on first bus if none selected
                  if (_selectedBusId == null && _busLocations[bus.id] != null) {
                    _focusOnBus(bus.id);
                  }
                });
              } else if (type == 'LOCATION_CLEARED') {
                setState(() {
                  _busLocations.remove(bus.id);
                  _updateCounts.remove(bus.id);
                });
              }
            } catch (e) {
              debugPrint('Error parsing location: $e');
            }
          },
          onError: (e) {
            debugPrint('WebSocket error for bus ${bus.id}: $e');
          },
          onDone: () {
            debugPrint('WebSocket closed for bus ${bus.id}');
          },
        );
      } catch (e) {
        debugPrint('Error connecting to bus ${bus.id}: $e');
      }
    }

    setState(() => _isConnected = true);
  }

  void _focusOnBus(int busId) {
    final location = _busLocations[busId];
    if (location != null) {
      _mapController.move(
        LatLng(location.latitude, location.longitude),
        15.0,
      );
    }
  }

  List<Marker> _buildMarkers() {
    List<Marker> markers = [];

    // College marker
    markers.add(
      Marker(
        width: 80,
        height: 80,
        point: LatLng(AppConfig.collegeLatitude, AppConfig.collegeLongitude),
        child: Tooltip(
          message: 'College',
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.red.withValues(alpha: 0.9),
              border: Border.all(color: Colors.white, width: 2),
            ),
            child: const Icon(Icons.school, color: Colors.white, size: 28),
          ),
        ),
      ),
    );

    // Pinned bus markers
    for (final entry in _busLocations.entries) {
      final busId = entry.key;
      final location = entry.value;

      if (location != null) {
        final isSelected = _selectedBusId == busId;

        markers.add(
          Marker(
            width: 80,
            height: 80,
            point: LatLng(location.latitude, location.longitude),
            child: GestureDetector(
              onTap: () {
                setState(() {
                  _selectedBusId = busId;
                });
                _focusOnBus(busId);
              },
              child: Tooltip(
                message: 'Bus ${location.busNumber}',
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isSelected ? Colors.orange : Colors.blue,
                    border: Border.all(
                      color: Colors.white,
                      width: isSelected ? 3 : 2,
                    ),
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                              color: Colors.orange.withValues(alpha: 0.5),
                              blurRadius: 8,
                              spreadRadius: 2,
                            )
                          ]
                        : [],
                  ),
                  child: Icon(
                    Icons.directions_bus,
                    color: Colors.white,
                    size: isSelected ? 36 : 32,
                  ),
                ),
              ),
            ),
          ),
        );
      }
    }

    return markers;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pinned Buses - Live Tracking'),
        elevation: 0,
        backgroundColor: Colors.blue,
        actions: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Center(
              child: _isConnected
                  ? Chip(
                      label: Text(
                        'Live • ${widget.pinnedBuses.length} buses',
                        style: const TextStyle(color: Colors.white),
                      ),
                      backgroundColor: Colors.green,
                      labelStyle: const TextStyle(color: Colors.white),
                    )
                  : Chip(
                      label: const Text('Connecting...',
                          style: TextStyle(color: Colors.white)),
                      backgroundColor: Colors.grey,
                      labelStyle: const TextStyle(color: Colors.white),
                    ),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          // Full-screen map
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: const LatLng(
                  AppConfig.collegeLatitude, AppConfig.collegeLongitude),
              initialZoom: 13.0,
              maxZoom: 19.0,
              minZoom: 5.0,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.busapp.victory',
              ),
              MarkerLayer(
                markers: _buildMarkers(),
              ),
            ],
          ),

          // Bottom tracking panel - scrollable cards
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: DraggableScrollableSheet(
              initialChildSize: 0.25,
              minChildSize: 0.15,
              maxChildSize: 0.6,
              builder: (context, scrollController) {
                return Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(20),
                      topRight: Radius.circular(20),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
                        blurRadius: 12,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: ListView(
                    controller: scrollController,
                    children: [
                      // Handle bar
                      Center(
                        child: Container(
                          margin: const EdgeInsets.only(top: 8, bottom: 8),
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.grey[300],
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),

                      // Title
                      const Padding(
                        padding:
                            EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: Text(
                          'Tracked Buses',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),

                      // Bus list cards
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Column(
                          children: widget.pinnedBuses.map((bus) {
                            final location = _busLocations[bus.id];
                            final isSelected = _selectedBusId == bus.id;
                            final updates = _updateCounts[bus.id] ?? 0;

                            return Container(
                              margin: const EdgeInsets.only(bottom: 10),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? Colors.orange.withValues(alpha: 0.05)
                                    : Colors.grey.withValues(alpha: 0.05),
                                border: Border.all(
                                  color: isSelected
                                      ? Colors.orange
                                      : Colors.grey[300]!,
                                  width: isSelected ? 2 : 1,
                                ),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  onTap: () {
                                    setState(() {
                                      _selectedBusId = bus.id;
                                    });
                                    if (location != null) {
                                      _focusOnBus(bus.id);
                                    }
                                  },
                                  borderRadius: BorderRadius.circular(12),
                                  child: Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            Row(
                                              children: [
                                                Container(
                                                  padding:
                                                      const EdgeInsets.all(8),
                                                  decoration: BoxDecoration(
                                                    color: Colors.blue
                                                        .withValues(alpha: 0.1),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            8),
                                                  ),
                                                  child: const Icon(
                                                    Icons.directions_bus,
                                                    color: Colors.blue,
                                                  ),
                                                ),
                                                const SizedBox(width: 12),
                                                Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      'Bus ${bus.busNumber}',
                                                      style: const TextStyle(
                                                        fontSize: 16,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                      ),
                                                    ),
                                                    Text(
                                                      bus.route,
                                                      style: TextStyle(
                                                        fontSize: 12,
                                                        color: Colors.grey[600],
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ],
                                            ),
                                            Column(
                                              children: [
                                                if (location != null)
                                                  Container(
                                                    width: 12,
                                                    height: 12,
                                                    decoration:
                                                        const BoxDecoration(
                                                      shape: BoxShape.circle,
                                                      color: Colors.green,
                                                    ),
                                                  )
                                                else
                                                  Container(
                                                    width: 12,
                                                    height: 12,
                                                    decoration:
                                                        const BoxDecoration(
                                                      shape: BoxShape.circle,
                                                      color: Colors.grey,
                                                    ),
                                                  ),
                                              ],
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 10),
                                        if (location != null) ...[
                                          Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.spaceBetween,
                                            children: [
                                              Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    'Speed',
                                                    style: TextStyle(
                                                      fontSize: 11,
                                                      color: Colors.grey[600],
                                                    ),
                                                  ),
                                                  Text(
                                                    '${location.speed.toStringAsFixed(1)} km/h',
                                                    style: const TextStyle(
                                                      fontSize: 14,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    'Updates',
                                                    style: TextStyle(
                                                      fontSize: 11,
                                                      color: Colors.grey[600],
                                                    ),
                                                  ),
                                                  Text(
                                                    '$updates',
                                                    style: const TextStyle(
                                                      fontSize: 14,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    'Last Update',
                                                    style: TextStyle(
                                                      fontSize: 11,
                                                      color: Colors.grey[600],
                                                    ),
                                                  ),
                                                  Text(
                                                    _formatTime(
                                                        location.timestamp),
                                                    style: const TextStyle(
                                                      fontSize: 12,
                                                      fontWeight:
                                                          FontWeight.w500,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ] else ...[
                                          Center(
                                            child: Text(
                                              'Waiting for location...',
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: Colors.grey[600],
                                                fontStyle: FontStyle.italic,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);

    if (diff.inSeconds < 60) {
      return 'now';
    } else if (diff.inMinutes < 60) {
      return '${diff.inMinutes}m ago';
    } else if (diff.inHours < 24) {
      return '${diff.inHours}h ago';
    } else {
      return '${diff.inDays}d ago';
    }
  }
}
