import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:agni_college_bus_tracker/services/location_service.dart';
import 'package:agni_college_bus_tracker/services/bus_service.dart';
import 'package:agni_college_bus_tracker/services/auth_service.dart';
import 'package:agni_college_bus_tracker/models/bus.dart';
import 'package:agni_college_bus_tracker/widgets/bus_tracking_map_widget.dart';
import 'package:agni_college_bus_tracker/services/live_tracking_service.dart';
import 'package:agni_college_bus_tracker/models/bus_location.dart';
import 'package:agni_college_bus_tracker/models/user.dart';
import 'package:latlong2/latlong.dart';

/// Compact Dashboard Tracking Widget
/// Shows live tracking for selected buses with expandable full-screen option
class DashboardTrackingWidget extends StatefulWidget {
  final String? preselectedBusNumber;
  final VoidCallback? onTrackingTap;

  const DashboardTrackingWidget({
    super.key,
    this.preselectedBusNumber,
    this.onTrackingTap,
  });

  @override
  State<DashboardTrackingWidget> createState() =>
      _DashboardTrackingWidgetState();
}

class _DashboardTrackingWidgetState extends State<DashboardTrackingWidget> {
  String? _selectedBusNumber;

  @override
  void initState() {
    super.initState();
    _selectedBusNumber = widget.preselectedBusNumber;
  }

  @override
  Widget build(BuildContext context) {
    final busService = context.watch<BusService>();
    final locService = context.watch<LocationService>();
    final liveTracking = context.watch<LiveTrackingService>();
    final authService = context.watch<AuthService>();
    final currentUser = authService.currentUser;

    // Filter buses based on student's pinned preferences
    final activeBuses = busService.buses.where((bus) {
      final isPinnedInProfile =
          currentUser?.pinnedBuses.contains(bus.busNumber) ?? false;

      return isPinnedInProfile;
    }).toList();

    if (activeBuses.isEmpty) return const SizedBox.shrink();

    // Auto-focus on the pinned bus from LiveTrackingService if available
    final focusedBusId = liveTracking.focusedBusId;
    if (focusedBusId != null &&
        activeBuses.any((b) => b.busNumber == focusedBusId)) {
      if (_selectedBusNumber != focusedBusId) {
        // Update selection in a microtask to avoid build-phase state changes
        Future.microtask(() {
          if (mounted) setState(() => _selectedBusNumber = focusedBusId);
        });
      }
    } else if (_selectedBusNumber == null && activeBuses.isNotEmpty) {
      _selectedBusNumber = activeBuses.first.busNumber;
    }

    // Validate selection against active list
    if (_selectedBusNumber != null &&
        !activeBuses.any((b) => b.busNumber == _selectedBusNumber)) {
      _selectedBusNumber =
          activeBuses.isNotEmpty ? activeBuses.first.busNumber : null;
    }

    final selectedBus = activeBuses.firstWhere(
      (b) => b.busNumber == _selectedBusNumber,
      orElse: () => activeBuses.first,
    );

    final bestLocation =
        locService.getBestLocationForBus(selectedBus.busNumber);
    final liveLocation = liveTracking.getLatestLocation(selectedBus.busNumber);

    BusLocation? selectedLocation;
    if (bestLocation != null) {
      selectedLocation = bestLocation;
    } else if (liveLocation != null) {
      // Map LiveLocation to BusLocation for compatibility with the map widget
      selectedLocation = BusLocation(
        busNumber: liveLocation.entityId,
        latitude: liveLocation.latitude,
        longitude: liveLocation.longitude,
        speed: liveLocation.speed,
        timestamp: liveLocation.timestamp,
        userType: UserRole.driver,
        isSharedByStudent: false,
      );
    }

    // Get boarding point location for marking on map if a tracking session exists
    LatLng? boardingPointLatLng;
    final busSessions = liveTracking.getSessionsForBus(selectedBus.busNumber);
    if (busSessions.isNotEmpty) {
      final loc = liveTracking
          .getBoardingPointLocation(busSessions.first.boardingPointId);
      if (loc != null) {
        boardingPointLatLng = LatLng(loc['latitude']!, loc['longitude']!);
      }
    }

    return Card(
      margin: const EdgeInsets.all(16),
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(
        children: [
          // Header with Bus Selection
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.location_on, color: Colors.blue),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Live Tracking',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey,
                        ),
                      ),
                      Text(
                        'Bus ${selectedBus.busNumber}',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue,
                        ),
                      ),
                    ],
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.refresh,
                          size: 20, color: Colors.blue),
                      onPressed: () async {
                        final messenger = ScaffoldMessenger.of(context);
                        await locService.refreshBusLocations();
                        if (mounted) {
                          messenger.showSnackBar(
                            const SnackBar(
                                content: Text('Tracking refreshed'),
                                duration: Duration(seconds: 1)),
                          );
                        }
                      },
                      constraints: const BoxConstraints(),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    IconButton(
                      icon: const Icon(Icons.fullscreen,
                          size: 20, color: Colors.blue),
                      onPressed: () =>
                          context.push('/track-bus-maps', extra: selectedBus),
                      constraints: const BoxConstraints(),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    DropdownButton<String>(
                      value: _selectedBusNumber,
                      underline: const SizedBox(),
                      style: const TextStyle(
                          fontSize: 14,
                          color: Colors.blue,
                          fontWeight: FontWeight.bold),
                      items: activeBuses
                          .map((bus) => DropdownMenuItem(
                              value: bus.busNumber,
                              child: Text('B${bus.busNumber}')))
                          .toList(),
                      onChanged: (value) {
                        if (value != null) {
                          setState(() => _selectedBusNumber = value);
                        }
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Map Widget
          selectedLocation != null
              ? BusTrackingMapWidget(
                  bus: selectedBus,
                  currentLocation: selectedLocation,
                  boardingPointLocation: boardingPointLatLng,
                  height: 180,
                  onMapReady: () {},
                )
              : Container(
                  height: 180,
                  color: Colors.blue.shade50,
                  child: const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 12),
                        Text('Connecting to live bus feed...',
                            style: TextStyle(color: Colors.blue)),
                      ],
                    ),
                  ),
                ),
        ],
      ),
    );
  }
}

/// Grid View for Multiple Buses Tracking
/// Shows small tracking cards for each bus
class MultipleTrackingGridWidget extends StatelessWidget {
  final int maxBusesDisplay;

  const MultipleTrackingGridWidget({
    super.key,
    this.maxBusesDisplay = 4,
  });

  @override
  Widget build(BuildContext context) {
    final busService = context.watch<BusService>();
    final locService = context.watch<LocationService>();

    final activeBuses = busService.buses
        .where((bus) => locService.getBestLocationForBus(bus.busNumber) != null)
        .take(maxBusesDisplay)
        .toList();

    if (activeBuses.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Active Buses Tracking',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.2,
            ),
            itemCount: activeBuses.length,
            itemBuilder: (context, index) {
              final bus = activeBuses[index];
              final location = locService.getBestLocationForBus(bus.busNumber)!;

              return _BusTrackingCard(
                bus: bus,
                location: location,
                onTap: () {
                  context.push('/track-bus-maps', extra: bus);
                },
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Individual Bus Tracking Card
class _BusTrackingCard extends StatelessWidget {
  final Bus bus;
  final dynamic location;
  final VoidCallback onTap;

  const _BusTrackingCard({
    required this.bus,
    required this.location,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Card(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        child: Stack(
          children: [
            // Background gradient
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.blue.shade50,
                    Colors.blue.shade100,
                  ],
                ),
              ),
            ),
            // Content
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Bus ${bus.busNumber}',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: _getSpeedColor(location.speed),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '${location.speed.toStringAsFixed(0)}',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    bus.route,
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const Spacer(),
                  Row(
                    children: [
                      const Icon(Icons.location_on,
                          size: 14, color: Colors.green),
                      const SizedBox(width: 4),
                      Text(
                        'Lat: ${location.latitude.toStringAsFixed(3)}',
                        style: const TextStyle(fontSize: 9),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      const Icon(Icons.location_on,
                          size: 14, color: Colors.green),
                      const SizedBox(width: 4),
                      Text(
                        'Lon: ${location.longitude.toStringAsFixed(3)}',
                        style: const TextStyle(fontSize: 9),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Align(
                    alignment: Alignment.bottomRight,
                    child:
                        Icon(Icons.arrow_forward, size: 16, color: Colors.grey),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _getSpeedColor(double speed) {
    if (speed < 5) return Colors.grey;
    if (speed < 30) return Colors.green;
    if (speed < 60) return Colors.orange;
    return Colors.red;
  }
}
