import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:agni_college_bus_tracker/models/bus_location.dart';
import 'package:agni_college_bus_tracker/models/bus.dart';
import 'package:agni_college_bus_tracker/config/app_config.dart';
import 'dart:math' as math;

/// Bus Tracking Map Widget with Direction, Speed, and Route Markers using FlutterMap
/// Shows real-time bus location with professional UI
class BusTrackingMapWidget extends StatefulWidget {
  final Bus bus;
  final BusLocation? currentLocation;
  final LatLng? boardingPointLocation;
  final List<BusLocation> routeHistory;
  final VoidCallback? onMapReady;
  final double height;

  const BusTrackingMapWidget({
    super.key,
    required this.bus,
    required this.currentLocation,
    this.boardingPointLocation,
    this.routeHistory = const [],
    this.onMapReady,
    this.height = 300,
  });

  @override
  State<BusTrackingMapWidget> createState() => _BusTrackingMapWidgetState();
}

class _BusTrackingMapWidgetState extends State<BusTrackingMapWidget> {
  late MapController mapController;
  final List<Marker> _markers = [];
  final List<LatLng> _routePolyline = [];

  @override
  void initState() {
    super.initState();
    mapController = MapController();
    _updateMapElements();
  }

  @override
  void didUpdateWidget(BusTrackingMapWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentLocation != widget.currentLocation ||
        oldWidget.bus != widget.bus) {
      _updateMapElements();
    }
  }

  void _updateMapElements() {
    if (!mounted) return;

    final location = widget.currentLocation;
    if (location == null) return;

    _markers.clear();
    _routePolyline.clear();

    // Add bus location marker (blue)
    _markers.add(
      Marker(
        point: LatLng(location.latitude, location.longitude),
        child: Icon(
          Icons.directions_bus,
          color: Colors.blue,
          size: 40,
        ),
      ),
    );

    // Add boarding point marker if available (green)
    if (widget.boardingPointLocation != null) {
      _markers.add(
        Marker(
          point: widget.boardingPointLocation!,
          child: const Icon(Icons.location_on, color: Colors.green, size: 40),
        ),
      );
    }

    // Add college destination marker (red)
    _markers.add(
      Marker(
        point:
            const LatLng(AppConfig.collegeLatitude, AppConfig.collegeLongitude),
        child: const Icon(Icons.school, color: Colors.red, size: 40),
      ),
    );

    // Update camera position
    try {
      mapController.move(
        LatLng(location.latitude, location.longitude),
        15,
      );
    } catch (e) {
      debugPrint('Error moving map: $e');
    }

    setState(() {});
  }

  /// Calculate bearing between two coordinates
  double _calculateBearing(double lat1, double lon1, double lat2, double lon2) {
    final lat1Rad = lat1 * math.pi / 180;
    final lat2Rad = lat2 * math.pi / 180;
    final lon2Rad = lon2 * math.pi / 180;
    final lon1Rad = lon1 * math.pi / 180;

    final y = math.sin(lon2Rad - lon1Rad) * math.cos(lat2Rad);
    final x = math.cos(lat1Rad) * math.sin(lat2Rad) -
        math.sin(lat1Rad) * math.cos(lat2Rad) * math.cos(lon2Rad - lon1Rad);
    return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
  }

  /// Calculate distance between two coordinates in kilometers
  double _calculateDistance(
      double lat1, double lon1, double lat2, double lon2) {
    const R = 6371; // Earth's radius in km
    final lat1Rad = lat1 * math.pi / 180;
    final lat2Rad = lat2 * math.pi / 180;
    final dLat = (lat2 - lat1) * math.pi / 180;
    final dLon = (lon2 - lon1) * math.pi / 180;

    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1Rad) *
            math.cos(lat2Rad) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return R * c;
  }

  @override
  void dispose() {
    mapController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final location = widget.currentLocation;

    return Container(
      height: widget.height,
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(12),
          bottomRight: Radius.circular(12),
        ),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: location == null
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.location_off, size: 48, color: Colors.grey),
                  const SizedBox(height: 12),
                  Text(
                    'No Location Data',
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                ],
              ),
            )
          : Stack(
              children: [
                FlutterMap(
                  mapController: mapController,
                  options: MapOptions(
                    initialCenter:
                        LatLng(location.latitude, location.longitude),
                    initialZoom: 15,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.busappvictory.app',
                    ),
                    MarkerLayer(markers: _markers),
                    PolylineLayer(
                      polylines: [
                        Polyline(
                          points: [
                            LatLng(location.latitude, location.longitude),
                            const LatLng(AppConfig.collegeLatitude,
                                AppConfig.collegeLongitude),
                          ],
                          color: Colors.blue.shade400,
                          strokeWidth: 2,
                        ),
                        if (widget.boardingPointLocation != null)
                          Polyline(
                            points: [
                              LatLng(location.latitude, location.longitude),
                              widget.boardingPointLocation!,
                            ],
                            color: Colors.blue.shade400,
                            strokeWidth: 2,
                          ),
                      ],
                    ),
                  ],
                ),
                // Info overlay at bottom
                Positioned(
                  bottom: 16,
                  left: 16,
                  right: 16,
                  child: Card(
                    elevation: 4,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Bus ${widget.bus.busNumber}',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              _InfoTile(
                                label: 'Speed',
                                value:
                                    '${location.speed.toStringAsFixed(1)} km/h',
                                icon: Icons.speed,
                                color: Colors.blue,
                              ),
                              _InfoTile(
                                label: 'Bearing',
                                value:
                                    '${_calculateBearing(location.latitude, location.longitude, AppConfig.collegeLatitude, AppConfig.collegeLongitude).toStringAsFixed(0)}°',
                                icon: Icons.navigation,
                                color: Colors.orange,
                              ),
                              _InfoTile(
                                label: 'Distance',
                                value:
                                    '${_calculateDistance(location.latitude, location.longitude, AppConfig.collegeLatitude, AppConfig.collegeLongitude).toStringAsFixed(1)} km',
                                icon: Icons.location_on,
                                color: Colors.red,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

/// Information Tile Widget - displays metric with icon and formatted value
class _InfoTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _InfoTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(fontSize: 10, color: Colors.grey),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }
}
