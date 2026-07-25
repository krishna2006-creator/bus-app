import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:agni_college_bus_tracker/config/app_config.dart';
import 'package:agni_college_bus_tracker/models/bus.dart';
import 'package:agni_college_bus_tracker/services/location_service.dart';

/// Full-screen live tracking map for a specific bus
class BusLiveTrackingMapScreen extends StatefulWidget {
  final Bus bus;

  const BusLiveTrackingMapScreen({super.key, required this.bus});

  @override
  State<BusLiveTrackingMapScreen> createState() =>
      _BusLiveTrackingMapScreenState();
}

class _BusLiveTrackingMapScreenState extends State<BusLiveTrackingMapScreen> {
  late MapController _mapController;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final locService = context.watch<LocationService>();
    final busLocation = locService.getBestLocationForBus(widget.bus.busNumber);

    final mapCenter = busLocation != null
        ? LatLng(busLocation.latitude, busLocation.longitude)
        : const LatLng(AppConfig.collegeLatitude, AppConfig.collegeLongitude);

    return Scaffold(
      appBar: AppBar(
        title: Text('Bus ${widget.bus.busNumber} - Live Tracking'),
        elevation: 0,
      ),
      body: Stack(
        children: [
          // Map
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: mapCenter,
              initialZoom: 14,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.busappvictory.app',
              ),
              MarkerLayer(
                markers: [
                  // College (destination)
                  Marker(
                    point: const LatLng(
                        AppConfig.collegeLatitude, AppConfig.collegeLongitude),
                    width: 50,
                    height: 50,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.red.withValues(alpha: 0.5),
                                blurRadius: 8,
                              ),
                            ],
                          ),
                          padding: const EdgeInsets.all(8),
                          child: const Icon(Icons.school,
                              color: Colors.white, size: 24),
                        ),
                        const Text('College',
                            style: TextStyle(fontSize: 10, color: Colors.red),
                            textAlign: TextAlign.center),
                      ],
                    ),
                  ),
                  // Bus location
                  if (busLocation != null)
                    Marker(
                      point:
                          LatLng(busLocation.latitude, busLocation.longitude),
                      width: 60,
                      height: 60,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.blue,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.blue.withValues(alpha: 0.5),
                                  blurRadius: 10,
                                  spreadRadius: 2,
                                ),
                              ],
                            ),
                            padding: const EdgeInsets.all(8),
                            child: const Icon(Icons.directions_bus,
                                color: Colors.white, size: 28),
                          ),
                          const Text('Bus',
                              style:
                                  TextStyle(fontSize: 10, color: Colors.blue),
                              textAlign: TextAlign.center),
                        ],
                      ),
                    ),
                ],
              ),
            ],
          ),

          // Info Card at bottom
          Positioned(
            bottom: 20,
            left: 16,
            right: 16,
            child: Card(
              elevation: 8,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.blue.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.directions_bus,
                              color: Colors.blue, size: 24),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Bus ${widget.bus.busNumber}',
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                widget.bus.route,
                                style: TextStyle(
                                  color: Colors.grey.shade600,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 16),
                    if (busLocation != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Speed',
                                  style: TextStyle(
                                      color: Colors.grey.shade600,
                                      fontSize: 12),
                                ),
                                Text(
                                  '${(busLocation.speed * 3.6).toStringAsFixed(1)} km/h',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  'Updated',
                                  style: TextStyle(
                                      color: Colors.grey.shade600,
                                      fontSize: 12),
                                ),
                                Text(
                                  _formatTime(busLocation.timestamp),
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          _mapController.move(mapCenter, 14);
                        },
                        icon: const Icon(Icons.my_location),
                        label: const Text('Center Map'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Close button
          Positioned(
            top: 0,
            left: 0,
            child: Container(),
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
    } else {
      return '${diff.inHours}h ago';
    }
  }
}
