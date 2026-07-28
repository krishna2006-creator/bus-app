import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:agni_college_bus_tracker/models/bus_location.dart';
import 'package:agni_college_bus_tracker/models/bus.dart';
import 'package:agni_college_bus_tracker/config/app_config.dart';
import 'dart:math' as math;

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
    this.height = 200,
  });

  @override
  State<BusTrackingMapWidget> createState() => _BusTrackingMapWidgetState();
}

class _BusTrackingMapWidgetState extends State<BusTrackingMapWidget> {
  late MapController mapController;
  final List<Marker> _markers = [];
  final List<LatLng> _routePolyline = [];
  LatLng? _previousPosition;

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

    final currentLatLng = LatLng(location.latitude, location.longitude);

    // Add route polyline with history
    if (widget.routeHistory.isNotEmpty) {
      _routePolyline.addAll(
        widget.routeHistory.map((loc) => LatLng(loc.latitude, loc.longitude)),
      );
    }

    // Add animated bus marker
    _markers.add(
      Marker(
        point: currentLatLng,
        width: 60,
        height: 60,
        child: Transform.rotate(
          angle: _previousPosition != null
              ? _calculateBearing(
                      _previousPosition!.latitude,
                      _previousPosition!.longitude,
                      location.latitude,
                      location.longitude) *
                  math.pi /
                  180
              : 0,
          child: Image.asset(
            'assets/bus_marker.jpg',
            fit: BoxFit.contain,
            width: 50,
            height: 50,
          ),
        ),
      ),
    );

    // Add boarding point marker
    if (widget.boardingPointLocation != null) {
      _markers.add(
        Marker(
          point: widget.boardingPointLocation!,
          width: 40,
          height: 40,
          child: const Icon(
            Icons.location_on,
            color: Colors.green,
            size: 40,
          ),
        ),
      );
    }

    // Add college destination marker
    _markers.add(
      Marker(
        point:
            const LatLng(AppConfig.collegeLatitude, AppConfig.collegeLongitude),
        width: 40,
        height: 40,
        child: const Icon(Icons.school, color: Colors.red, size: 40),
      ),
    );

    _previousPosition = currentLatLng;

    // Smooth camera animation
    try {
      mapController.move(currentLatLng, 15);
    } catch (e) {
      debugPrint('Error moving map: $e');
    }

    setState(() {});
  }

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

  double _calculateDistance(
      double lat1, double lon1, double lat2, double lon2) {
    const R = 6371;
    final lat1Rad = lat1 * math.pi / 180;
    final lat2Rad = lat2 * math.pi / 180;
    final dLat = (lat2 - lat1) * math.pi / 180;
    final dLon = (lon2 - lon1) * math.pi / 180;

    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1Rad) *
            math.cos(lat2Rad) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return R * c;
  }

  String _calculateETA(BusLocation location) {
    final distance = _calculateDistance(
      location.latitude,
      location.longitude,
      AppConfig.collegeLatitude,
      AppConfig.collegeLongitude,
    );
    if (location.speed <= 0) return '-- min';
    final minutes = (distance / location.speed * 60).round();
    if (minutes < 1) return '<1 min';
    return '$minutes min';
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
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.location_off, size: 48, color: Colors.grey),
                  SizedBox(height: 12),
                  Text('No Location Data',
                      style: TextStyle(color: Colors.grey)),
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
                          'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
                      subdomains: const ['a', 'b', 'c'],
                      userAgentPackageName: 'com.busappvictory.app',
                    ),
                    MarkerLayer(markers: _markers),
                    if (_routePolyline.length > 1)
                      PolylineLayer(
                        polylines: [
                          Polyline(
                            points: _routePolyline,
                            color: Colors.blue.shade400,
                            strokeWidth: 4,
                          ),
                        ],
                      ),
                    PolylineLayer(
                      polylines: [
                        Polyline(
                          points: [
                            LatLng(location.latitude, location.longitude),
                            const LatLng(AppConfig.collegeLatitude,
                                AppConfig.collegeLongitude),
                          ],
                          color: Colors.red.shade400,
                          strokeWidth: 3,
                        ),
                        if (widget.boardingPointLocation != null)
                          Polyline(
                            points: [
                              LatLng(location.latitude, location.longitude),
                              widget.boardingPointLocation!,
                            ],
                            color: Colors.green.shade400,
                            strokeWidth: 3,
                          ),
                      ],
                    ),
                  ],
                ),
                Positioned(
                  bottom: 16,
                  left: 16,
                  right: 16,
                  child: Card(
                    elevation: 6,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: Colors.blue.shade50,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(Icons.directions_bus,
                                    color: Colors.blue),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Bus ${widget.bus.busNumber}',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16),
                                    ),
                                    Text(
                                      widget.bus.route,
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey.shade600),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
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
                                label: 'Distance',
                                value:
                                    '${_calculateDistance(location.latitude, location.longitude, AppConfig.collegeLatitude, AppConfig.collegeLongitude).toStringAsFixed(1)} km',
                                icon: Icons.location_on,
                                color: Colors.red,
                              ),
                              _InfoTile(
                                label: 'ETA',
                                value: _calculateETA(location),
                                icon: Icons.access_time,
                                color: Colors.purple,
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
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: color, size: 18),
        ),
        const SizedBox(height: 4),
        Text(label,
            style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
        Text(value,
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.bold, color: color)),
      ],
    );
  }
}
