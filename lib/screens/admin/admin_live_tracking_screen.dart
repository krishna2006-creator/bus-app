import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:agni_college_bus_tracker/config/app_config.dart';
import 'package:agni_college_bus_tracker/models/bus_location.dart';
import 'package:agni_college_bus_tracker/models/user.dart';
import 'package:agni_college_bus_tracker/services/auth_service.dart';
import 'package:agni_college_bus_tracker/services/location_service.dart';
import 'package:agni_college_bus_tracker/services/pinned_bus_monitor_service.dart';

/// Embeddable (Scaffold-free) live bus tracking map.
///
/// This is the map portion shared by the admin live-tracking route AND the
/// student / staff dashboards. It does NOT own a [Scaffold] or [AppBar], so
/// embedding it inside a dashboard no longer produces the nested-Scaffold
/// "double screen" / jank that happened before.
///
/// It manages exactly one [MapController] and one refresh timer, so embedding
/// it once is cheap and fast.
class AdminLiveTrackingMapView extends StatefulWidget {
  /// When true, only buses the current user has pinned are rendered.
  final bool showOnlyPinnedBuses;

  /// When true, the compact status bar is rendered below the map.
  final bool showStatusBar;

  /// When true, a compact ETA card for each pinned bus is appended.
  final bool showPinnedStatus;

  /// Fixed height of the map widget. Using a fixed height (instead of
  /// [Expanded]) makes this view safe to embed in scroll views and columns.
  final double mapHeight;

  const AdminLiveTrackingMapView({
    super.key,
    this.showOnlyPinnedBuses = false,
    this.showStatusBar = true,
    this.showPinnedStatus = false,
    this.mapHeight = 260,
  });

  @override
  State<AdminLiveTrackingMapView> createState() =>
      _AdminLiveTrackingMapViewState();
}

class _AdminLiveTrackingMapViewState extends State<AdminLiveTrackingMapView> {
  final MapController _mapController = MapController();
  Timer? _refreshTimer;
  List<Marker> _allMarkers = [];
  int _visibleBusCount = 0;
  String _lastUpdateTime = 'Updating...';
  bool _isAutoRefresh = true;

  int get visibleBusCount => _visibleBusCount;
  String get lastUpdateTime => _lastUpdateTime;
  bool get isAutoRefresh => _isAutoRefresh;

  /// Triggered by the parent screen's AppBar refresh button.
  Future<void> refreshNow() => _updateMapElements();

  @override
  void initState() {
    super.initState();
    _startAutoRefresh();
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateMapElements());
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
    // 1 second polling keeps the live feel snappy.
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
    final user = authService.currentUser;

    final allLocations = locationService.allLocations.values.toList();

    List<BusLocation> locationsToShow = allLocations;
    if (widget.showOnlyPinnedBuses && user != null) {
      locationsToShow = allLocations
          .where((loc) => user.pinnedBuses.contains(loc.busNumber))
          .toList();
    }

    final markers = <Marker>[];

    // College marker
    markers.add(
      Marker(
        point: const LatLng(
          AppConfig.collegeLatitude,
          AppConfig.collegeLongitude,
        ),
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
                ),
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

    // Bus / user markers
    for (final loc in locationsToShow) {
      final isBus = loc.userType == UserRole.driver;
      final isPinned =
          user != null && user.pinnedBuses.contains(loc.busNumber);
      markers.add(
        Marker(
          point: LatLng(loc.latitude, loc.longitude),
          child: Tooltip(
            message: _busTooltip(loc, isPinned),
            child: Container(
              decoration: BoxDecoration(
                color: isPinned
                    ? Colors.green
                    : (isBus ? Colors.orange : Colors.blue),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withAlpha(100),
                    blurRadius: 5,
                  ),
                ],
              ),
              child: Icon(
                isBus ? Icons.directions_bus : Icons.person,
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

  String _busTooltip(BusLocation loc, bool isPinned) {
    var tooltip = 'Bus #${loc.busNumber}\n';
    tooltip += 'Speed: ${loc.speed.toStringAsFixed(1)} km/h';
    if (isPinned) {
      final monitor = context.read<PinnedBusMonitorService>();
      final data = monitor.trackingData[loc.busNumber];
      if (data != null) {
        tooltip += '\nStatus: ${data.statusLabel}';
        tooltip += '\nDistance: ${data.distanceKm.toStringAsFixed(2)} km';
        tooltip += '\nETA: ${data.etaMinutes} min';
      }
    }
    tooltip += '\nUpdated: ${loc.timestamp.toString().split('.')[0]}';
    return tooltip;
  }

  @override
  Widget build(BuildContext context) {
    final authService = context.watch<AuthService>();
    final user = authService.currentUser;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: widget.mapHeight,
          child: FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: const LatLng(
                AppConfig.collegeLatitude,
                AppConfig.collegeLongitude,
              ),
              initialZoom: AppConfig.defaultZoom,
            ),
            children: [
              TileLayer(
                urlTemplate:
                    'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.busappvictory.app',
              ),
              MarkerLayer(markers: _allMarkers),
            ],
          ),
        ),
        if (widget.showStatusBar) _buildStatusBar(),
        if (widget.showPinnedStatus &&
            user != null &&
            user.pinnedBuses.isNotEmpty)
          _buildPinnedStatus(context, user),
      ],
    );
  }

  Widget _buildPinnedStatus(BuildContext context, User user) {
    final pinnedMonitor = context.watch<PinnedBusMonitorService>();
    final data = pinnedMonitor.trackingData;

    return Container(
      color: Colors.grey.shade100,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Text(
              'Pinned Buses',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: user.pinnedBuses.length,
            separatorBuilder: (_, __) => const SizedBox(height: 4),
            itemBuilder: (context, index) {
              final busNumber = user.pinnedBuses[index];
              final track = data[busNumber];
              return Card(
                margin: EdgeInsets.zero,
                child: ListTile(
                  leading: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
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
                  title: Text(
                    'Bus $busNumber',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  subtitle: Text(
                    track != null
                        ? track.statusLabel
                        : 'Waiting for location...',
                    style: const TextStyle(fontSize: 12),
                  ),
                  trailing: track != null
                      ? Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              '${track.etaMinutes} min',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: Colors.deepOrange,
                              ),
                            ),
                            Text(
                              '${track.distanceKm.toStringAsFixed(2)} km',
                              style: const TextStyle(
                                fontSize: 11,
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        )
                      : null,
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.deepOrange.withAlpha(230),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(26),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
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
              decoration: BoxDecoration(
                color: Colors.grey,
                shape: BoxShape.circle,
              ),
            ),
        ],
      ),
    );
  }
}

/// Admin Live Bus Tracking Screen using flutter_map.
/// Real-time visualization of all buses and student locations.
class AdminLiveTrackingScreen extends StatefulWidget {
  const AdminLiveTrackingScreen({super.key});

  @override
  State<AdminLiveTrackingScreen> createState() =>
      _AdminLiveTrackingScreenState();
}

class _AdminLiveTrackingScreenState extends State<AdminLiveTrackingScreen> {
  final _mapViewKey = GlobalKey<_AdminLiveTrackingMapViewState>();

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
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

    final locationService = context.watch<LocationService>();
    final buses = locationService.allLocations.values.toList();

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
            icon: Icon(_mapViewKey.currentState?.isAutoRefresh ?? true
                ? Icons.pause
                : Icons.play_arrow),
            onPressed: () {
              final st = _mapViewKey.currentState;
              if (st == null) return;
              st._isAutoRefresh = !(st._isAutoRefresh);
              setState(() {});
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _mapViewKey.currentState?.refreshNow(),
          ),
        ],
      ),
      body: Column(
        children: [
          // Live tracking map (embeddable, no nested Scaffold)
          AdminLiveTrackingMapView(
            key: _mapViewKey,
            mapHeight: 320,
          ),
          // Bus list
          Expanded(
            child: Container(
              color: Colors.grey.shade100,
              child: buses.isEmpty
                  ? const Center(child: Text('No buses online'))
                  : ListView.builder(
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
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
