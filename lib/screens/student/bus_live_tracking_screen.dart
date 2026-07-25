import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:agni_college_bus_tracker/services/live_tracking_service.dart';
import 'package:agni_college_bus_tracker/services/distance_calculator.dart'
    as dist;
import 'package:agni_college_bus_tracker/models/tracking_models.dart';
import 'package:agni_college_bus_tracker/config/app_config.dart';

/// Delivery-App Style Real-Time Bus Tracking Screen using flutter_map
/// Shows live tracking similar to Swiggy, Zomato, Amazon delivery
class BusLiveTrackingScreen extends StatefulWidget {
  final TrackingSession trackingSession;
  final BusRoute busRoute;

  const BusLiveTrackingScreen({
    super.key,
    required this.trackingSession,
    required this.busRoute,
  });

  @override
  State<BusLiveTrackingScreen> createState() => _BusLiveTrackingScreenState();
}

class _BusLiveTrackingScreenState extends State<BusLiveTrackingScreen> {
  final MapController _mapController = MapController();
  late List<LatLng> _routePolyline = [];
  bool _showDetails = false;

  @override
  void initState() {
    super.initState();
    _initializeTracking();
  }

  Future<void> _initializeTracking() async {
    try {
      // Get route polyline from distance calculator
      final polyline = await dist.DistanceCalculator.getRoutePolyline(
        widget.busRoute.boardingPoints.first.latitude,
        widget.busRoute.boardingPoints.first.longitude,
        AppConfig.collegeLatitude,
        AppConfig.collegeLongitude,
      );

      setState(() {
        _routePolyline = polyline.isNotEmpty
            ? polyline.map((p) => LatLng(p.latitude, p.longitude)).toList()
            : [
                LatLng(widget.busRoute.boardingPoints.first.latitude,
                    widget.busRoute.boardingPoints.first.longitude),
                LatLng(AppConfig.collegeLatitude, AppConfig.collegeLongitude),
              ];
      });
    } catch (e) {
      debugPrint('Error initializing tracking: $e');
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updateMap();
  }

  void _updateMap() {
    final tracking = context.watch<LiveTrackingService>();
    final busLocation =
        tracking.getLatestLocation('bus_${widget.trackingSession.busId}');
    if (busLocation != null) {
      try {
        _mapController.move(
          LatLng(busLocation.latitude, busLocation.longitude),
          15,
        );
      } catch (e) {
        debugPrint('Error moving map: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tracking = context.watch<LiveTrackingService>();
    final session = tracking.getSession(widget.trackingSession.id) ??
        widget.trackingSession;
    final boardingPoint = widget.busRoute.boardingPoints.first;
    final busLocation =
        tracking.getLatestLocation('bus_${widget.trackingSession.busId}');

    List<Marker> markers = [
      // Boarding point marker (green)
      Marker(
        point: LatLng(boardingPoint.latitude, boardingPoint.longitude),
        child: Tooltip(
          message: 'Pickup Point',
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
            child: const Icon(Icons.location_on, color: Colors.white, size: 30),
          ),
        ),
      ),
      // College destination marker (red)
      Marker(
        point: LatLng(AppConfig.collegeLatitude, AppConfig.collegeLongitude),
        child: Tooltip(
          message: AppConfig.collegeName,
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
            child: const Icon(Icons.school, color: Colors.white, size: 30),
          ),
        ),
      ),
    ];

    // Add bus marker if location available (blue)
    if (busLocation != null) {
      markers.add(
        Marker(
          point: LatLng(busLocation.latitude, busLocation.longitude),
          child: Tooltip(
            message:
                'Bus Location\nSpeed: ${busLocation.speed.toStringAsFixed(1)} km/h',
            child: Transform.rotate(
              angle: busLocation.bearing * 3.14159 / 180,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.blue,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withAlpha(100),
                      blurRadius: 5,
                    )
                  ],
                ),
                child: const Icon(Icons.directions_bus,
                    color: Colors.white, size: 30),
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Track Your Bus'),
        centerTitle: true,
        backgroundColor: Colors.blueAccent,
        elevation: 0,
      ),
      body: Stack(
        children: [
          // Flutter Map - positioned to fill available space
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            bottom: 0,
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter:
                    LatLng(boardingPoint.latitude, boardingPoint.longitude),
                initialZoom: 15,
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.busappvictory.app',
                ),
                PolylineLayer(
                  polylines: [
                    if (_routePolyline.isNotEmpty)
                      Polyline(
                        points: _routePolyline,
                        color: Colors.blue.withAlpha(150),
                        strokeWidth: 5,
                      ),
                  ],
                ),
                MarkerLayer(markers: markers),
              ],
            ),
          ),

          // Bottom Sheet - Live Tracking Info with proper spacing from bottom
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            height: _showDetails ? 350 : 200,
            child: GestureDetector(
              onTap: () {
                setState(() => _showDetails = !_showDetails);
              },
              child: SingleChildScrollView(
                physics: const ClampingScrollPhysics(),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(20),
                      topRight: Radius.circular(20),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withAlpha(100),
                        blurRadius: 10,
                        offset: const Offset(0, -5),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Handle bar
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.grey[300],
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),

                      // Main tracking info
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            // Distance and time
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceAround,
                              children: [
                                _buildInfoBox(
                                  icon: Icons.location_on,
                                  label: 'Distance',
                                  value: _formatDistance(session.distanceToBus),
                                  color: Colors.blue,
                                ),
                                _buildInfoBox(
                                  icon: Icons.schedule,
                                  label: 'ETA',
                                  value: '${session.estimatedMinutesToBus} min',
                                  color: Colors.orange,
                                ),
                                _buildInfoBox(
                                  icon: Icons.speed,
                                  label: 'Status',
                                  value: _getStatusText(session.status),
                                  color: Colors.green,
                                ),
                              ],
                            ),

                            const SizedBox(height: 16),

                            // Status progress
                            _buildStatusProgress(session),

                            if (_showDetails) ...[
                              const SizedBox(height: 16),
                              _buildDetailedInfo(session),
                            ],
                          ],
                        ),
                      ),

                      // Action buttons
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: () async {
                                  // Refresh location
                                  try {
                                    await Future.delayed(
                                        const Duration(milliseconds: 500));
                                    if (context.mounted) {
                                      _updateMap();
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        const SnackBar(
                                            content: Text('Location refreshed'),
                                            duration: Duration(seconds: 1)),
                                      );
                                    }
                                  } catch (e) {
                                    debugPrint('Error refreshing: $e');
                                  }
                                },
                                icon: const Icon(Icons.refresh),
                                label: const Text('Refresh'),
                                style: ElevatedButton.styleFrom(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 12),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: () async {
                                  // Stop tracking
                                  try {
                                    await tracking.stopTracking(session.id);
                                    if (!context.mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Tracking stopped'),
                                        duration: Duration(seconds: 1),
                                      ),
                                    );
                                    await Future.delayed(
                                        const Duration(milliseconds: 500));
                                    if (context.mounted) {
                                      Navigator.of(context).pop();
                                    }
                                  } catch (e) {
                                    debugPrint('Error stopping tracking: $e');
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        SnackBar(content: Text('Error: $e')),
                                      );
                                    }
                                  }
                                },
                                icon: const Icon(Icons.stop),
                                label: const Text('Done'),
                                style: ElevatedButton.styleFrom(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 12),
                                  backgroundColor: Colors.red,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoBox({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Column(
      children: [
        Icon(icon, color: color, size: 32),
        const SizedBox(height: 8),
        Text(
          value,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[600],
          ),
        ),
      ],
    );
  }

  Widget _buildStatusProgress(TrackingSession session) {
    final steps = [
      ('Pickup', TrackingStatus.trackingToBoarding),
      ('Arriving', TrackingStatus.atBoarding),
      ('To College', TrackingStatus.trackingToCollege),
      ('Arrived', TrackingStatus.completed),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Journey Progress',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Colors.grey,
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 8,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: _getProgressValue(session.status),
              minHeight: 8,
              backgroundColor: Colors.grey[300],
              valueColor: AlwaysStoppedAnimation<Color>(
                _getProgressColor(session.status),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: steps.map((step) {
            final isActive = _isStatusActive(session.status, step.$2);
            return Flexible(
              child: Column(
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isActive ? Colors.blue : Colors.grey[300],
                    ),
                    child: isActive
                        ? const Icon(Icons.check, size: 16, color: Colors.white)
                        : null,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    step.$1,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 10,
                      color: isActive ? Colors.blue : Colors.grey,
                      fontWeight:
                          isActive ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildDetailedInfo(TrackingSession session) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildDetailRow(
              'To Boarding', _formatDistance(session.distanceToBus)),
          _buildDetailRow(
              'To College', _formatDistance(session.totalDistanceToCollege)),
          _buildDetailRow('Pickup', widget.busRoute.boardingPoints.first.name),
          _buildDetailRow('Destination', AppConfig.collegeName),
          _buildDetailRow('Started', _formatTime(session.startTime)),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: Colors.grey,
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  String _formatDistance(double distanceKm) {
    if (distanceKm < 1) {
      return '${(distanceKm * 1000).toStringAsFixed(0)} m';
    }
    return '${distanceKm.toStringAsFixed(2)} km';
  }

  String _formatTime(DateTime time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  String _getStatusText(TrackingStatus status) {
    switch (status) {
      case TrackingStatus.trackingToBoarding:
        return 'Coming';
      case TrackingStatus.atBoarding:
        return 'Arriving';
      case TrackingStatus.trackingToCollege:
        return 'On Way';
      case TrackingStatus.completed:
        return 'Arrived';
    }
  }

  double _getProgressValue(TrackingStatus status) {
    switch (status) {
      case TrackingStatus.trackingToBoarding:
        return 0.25;
      case TrackingStatus.atBoarding:
        return 0.50;
      case TrackingStatus.trackingToCollege:
        return 0.75;
      case TrackingStatus.completed:
        return 1.0;
    }
  }

  Color _getProgressColor(TrackingStatus status) {
    switch (status) {
      case TrackingStatus.trackingToBoarding:
        return Colors.orange;
      case TrackingStatus.atBoarding:
        return Colors.amber;
      case TrackingStatus.trackingToCollege:
        return Colors.lightBlue;
      case TrackingStatus.completed:
        return Colors.green;
    }
  }

  bool _isStatusActive(TrackingStatus current, TrackingStatus target) {
    final statusOrder = [
      TrackingStatus.trackingToBoarding,
      TrackingStatus.atBoarding,
      TrackingStatus.trackingToCollege,
      TrackingStatus.completed,
    ];

    final currentIndex = statusOrder.indexOf(current);
    final targetIndex = statusOrder.indexOf(target);

    return targetIndex <= currentIndex;
  }

  @override
  void dispose() {
    try {
      _mapController.dispose();
    } catch (e) {
      debugPrint('Error disposing map: $e');
    }
    super.dispose();
  }
}
