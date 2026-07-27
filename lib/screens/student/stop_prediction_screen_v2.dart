import 'package:flutter/material.dart';
import 'dart:async';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import 'package:agni_college_bus_tracker/models/prediction_models.dart';
import 'package:agni_college_bus_tracker/providers/stop_prediction_provider.dart';
import 'package:agni_college_bus_tracker/services/live_tracking_service.dart';
import 'package:agni_college_bus_tracker/config/app_config.dart';

/// Flutter Map based Stop Prediction Screen - Google Maps style
/// Full screen map with floating search, markers, and bottom sheet UI
class StopPredictionScreenV2 extends StatefulWidget {
  const StopPredictionScreenV2({super.key});

  @override
  State<StopPredictionScreenV2> createState() => _StopPredictionScreenV2State();
}

class _StopPredictionScreenV2State extends State<StopPredictionScreenV2> {
  late MapController _mapController;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  Timer? _debounce;

  bool _isSearchFocused = false;

  final LatLng _initialCenter =
      LatLng(AppConfig.collegeLatitude, AppConfig.collegeLongitude);
  final double _zoomLevel = 14.0;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    _searchController.addListener(_onSearchChanged);
    _searchFocus.addListener(_onSearchFocusChanged);

    // Initialize stop prediction provider
    Future.microtask(() {
      if (!mounted) return;
      final provider = context.read<StopPredictionProvider>();
      final liveTracking = context.read<LiveTrackingService>();
      provider.setLiveTrackingService(liveTracking);
      provider.initAsync();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    _mapController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged() {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) {
        setState(() {}); // Refresh UI state for clear button visibility
        final provider = context.read<StopPredictionProvider>();
        provider.searchStops(_searchController.text);

        // Auto-zoom to fit search results if we have matches
        if (provider.searchResults.isNotEmpty &&
            _searchController.text.isNotEmpty) {
          _fitSearchMarkers(provider.searchResults);
        }
      }
    });
  }

  void _fitSearchMarkers(List<BusStop> stops) {
    if (stops.isEmpty) return;

    final points = stops.map((s) => s.location).toList();
    final bounds = LatLngBounds.fromPoints(points);

    _mapController.fitCamera(
      CameraFit.bounds(
        bounds: bounds,
        padding:
            const EdgeInsets.only(top: 100, left: 50, right: 50, bottom: 250),
      ),
    );
  }

  void _onSearchFocusChanged() {
    setState(() {
      _isSearchFocused = _searchFocus.hasFocus;
    });
  }

  void _selectStop(BusStop stop) {
    final provider = context.read<StopPredictionProvider>();
    provider.setPreviewStop(stop);
    _searchController.text = stop.name; // Keep the name in the bar for context
    _searchFocus.unfocus();
    setState(() => _isSearchFocused = false);

    // Move camera to stop
    _mapController.move(stop.location, 17);
  }

  Future<void> _confirmSelection() async {
    final provider = context.read<StopPredictionProvider>();
    final previewStop = provider.previewStop;

    if (previewStop != null) {
      await provider.selectStop(previewStop);
      if (!mounted) return;
      if (provider.error == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Boarding stop set: ${previewStop.name}'),
            duration: const Duration(seconds: 2),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Unable to set boarding stop: ${provider.error}'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  void _changeStop() {
    final provider = context.read<StopPredictionProvider>();
    _searchController.clear();
    provider.clearSelection();
    _searchFocus.requestFocus();
  }

  void _centerToCurrentLocation() async {
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings:
            const LocationSettings(accuracy: LocationAccuracy.high),
      );

      _mapController.move(
        LatLng(position.latitude, position.longitude),
        17,
      );
    } catch (e) {
      debugPrint('Error getting location: $e');
    }
  }

  List<Marker> _buildMarkers(StopPredictionProvider provider) {
    final selectedStop = provider.selectedStop;
    final previewStop = provider.previewStop;
    final busLocation = provider.liveBusLocation;

    List<Marker> markers = [];

    // College marker
    markers.add(
      Marker(
        width: 80,
        height: 80,
        point: LatLng(AppConfig.collegeLatitude, AppConfig.collegeLongitude),
        child: Tooltip(
          message: 'College',
          child: Icon(Icons.school, color: Colors.red, size: 32),
        ),
      ),
    );

    // Selected stop marker
    if (selectedStop != null) {
      markers.add(
        Marker(
          width: 80,
          height: 80,
          point: selectedStop.location,
          child: Tooltip(
            message: selectedStop.name,
            child: Icon(Icons.location_on, color: Colors.green, size: 32),
          ),
        ),
      );
    }

    // Preview stop marker
    if (previewStop != null) {
      final isExternal = previewStop.id < 0;
      markers.add(
        Marker(
          width: 80,
          height: 80,
          point: previewStop.location,
          child: Tooltip(
            message: previewStop.name,
            child: Icon(
              Icons.location_on,
              color: isExternal ? Colors.orange : Colors.blue,
              size: isExternal ? 40 : 32,
            ),
          ),
        ),
      );
    }

    // Bus location marker
    if (busLocation != null) {
      markers.add(
        Marker(
          width: 80,
          height: 80,
          point: LatLng(busLocation.latitude, busLocation.longitude),
          child: Tooltip(
            message: 'Bus',
            child: Icon(Icons.directions_bus, color: Colors.orange, size: 32),
          ),
        ),
      );
    }

    // Search Result Markers (Secondary markers) - Always show current search results
    for (var stop in provider.searchResults) {
      // Skip if this is the active/preview stop (already has a primary marker)
      if (stop.id == selectedStop?.id || stop.id == previewStop?.id) continue;

      markers.add(
        Marker(
          width: 40,
          height: 40,
          point: stop.location,
          child: GestureDetector(
            onTap: () => _selectStop(stop),
            child: Tooltip(
              message: stop.name,
              child:
                  const Icon(Icons.location_on, color: Colors.grey, size: 28),
            ),
          ),
        ),
      );
    }

    return markers;
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<StopPredictionProvider>(
      builder: (context, provider, _) {
        final selectedStop = provider.selectedStop;
        final previewStop = provider.previewStop;
        final prediction = provider.prediction;
        final activeStop = selectedStop ?? previewStop;

        return Scaffold(
          body: Stack(
            children: [
              // Full Screen Map
              FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  onTap: (tapPos, point) {
                    context
                        .read<StopPredictionProvider>()
                        .searchByLocation(point);
                  },
                  initialCenter: _initialCenter,
                  initialZoom: _zoomLevel,
                  maxZoom: 19.0,
                  minZoom: 5.0,
                ),
                children: [
                  TileLayer(
                    urlTemplate:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.busapp.victory',
                  ),
                  MarkerLayer(
                    markers: _buildMarkers(provider),
                  ),
                ],
              ),

              // Error Notification Overlay
              if (provider.error != null)
                Positioned(
                  top: 100,
                  left: 20,
                  right: 20,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.9),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      provider.error!,
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),

              // Search Bar (Top)
              Positioned(
                top: 16,
                left: 16,
                right: 16,
                child: SafeArea(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(50),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.1),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: TextField(
                      controller: _searchController,
                      focusNode: _searchFocus,
                      decoration: InputDecoration(
                        hintText: 'Search boarding stop...',
                        border: InputBorder.none,
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: provider.isLoading
                            ? const Padding(
                                padding: EdgeInsets.all(12),
                                child: SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2)),
                              )
                            : _searchController.text.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.close),
                                    onPressed: () {
                                      _searchController.clear();
                                      provider.searchStops('');
                                      setState(() => _isSearchFocused = false);
                                    },
                                  )
                                : null,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              // Search Results Dropdown
              if (_isSearchFocused &&
                  provider.searchResults.isNotEmpty &&
                  (_searchController.text.isNotEmpty ||
                      provider.searchResults.length !=
                          provider.allStops.length))
                Positioned(
                  top: 80,
                  left: 16,
                  right: 16,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.15),
                          blurRadius: 12,
                        ),
                      ],
                    ),
                    constraints: const BoxConstraints(maxHeight: 400),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: provider.searchResults.length,
                      itemBuilder: (context, index) {
                        final stop = provider.searchResults[index];
                        return Material(
                          child: ListTile(
                            leading: Icon(
                              Icons.location_on,
                              color: stop.id == activeStop?.id
                                  ? Colors.blue
                                  : Colors.grey,
                            ),
                            title: Text(
                              stop.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            subtitle: Text(
                              '${stop.location.latitude.toStringAsFixed(4)}, '
                              '${stop.location.longitude.toStringAsFixed(4)}',
                              style: const TextStyle(fontSize: 11),
                            ),
                            onTap: () => _selectStop(stop),
                          ),
                        );
                      },
                    ),
                  ),
                ),

              // Current Location Button
              Positioned(
                right: 16,
                bottom: 100,
                child: FloatingActionButton(
                  mini: true,
                  backgroundColor: Colors.blue,
                  onPressed: _centerToCurrentLocation,
                  child: const Icon(Icons.my_location),
                ),
              ),

              // Bottom Sheet - Stop Details & Actions
              if (activeStop != null && !_isSearchFocused)
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(20),
                        topRight: Radius.circular(20),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black12,
                          blurRadius: 10,
                          offset: Offset(0, -2),
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Handle bar
                          Center(
                            child: Container(
                              width: 40,
                              height: 4,
                              decoration: BoxDecoration(
                                color: Colors.grey[300],
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),

                          // Stop name and distance
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: Colors.blue.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(
                                  Icons.location_on,
                                  color: Colors.blue,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      activeStop.name,
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    if (prediction != null)
                                      Text(
                                        '${prediction.distanceKm.toStringAsFixed(1)} km away',
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: Colors.grey[600],
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),

                          // ETA information
                          if (prediction != null) ...[
                            const SizedBox(height: 16),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.grey[100],
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'ETA',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey[600],
                                        ),
                                      ),
                                      Text(
                                        '${prediction.etaMinutes} min',
                                        style: const TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                  Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Distance',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey[600],
                                        ),
                                      ),
                                      Text(
                                        '${prediction.distanceKm.toStringAsFixed(1)} km',
                                        style: const TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                  Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Status',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey[600],
                                        ),
                                      ),
                                      Text(
                                        prediction.trafficLevel,
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
                          ],

                          const SizedBox(height: 20),

                          // Action Buttons
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton(
                                  onPressed: _changeStop,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.grey[200],
                                    foregroundColor: Colors.black,
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 14),
                                  ),
                                  child: const Text(
                                    'Change Stop',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: ElevatedButton(
                                  onPressed: _confirmSelection,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.blue,
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 14),
                                  ),
                                  child: const Text(
                                    'Set Boarding Stop',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          // Stop Tracking Button - clears tracking state and stops updates
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: () async {
                                await context
                                    .read<StopPredictionProvider>()
                                    .stopTracking();
                                if (context.mounted) Navigator.pop(context);
                              },
                              icon: const Icon(Icons.stop_circle,
                                  color: Colors.red),
                              label: const Text(
                                'Stop Tracking',
                                style: TextStyle(
                                  color: Colors.red,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: Colors.red),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

              // Instruction when no stop selected
              if (activeStop == null && !_isSearchFocused)
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
                      children: [
                        const Icon(
                          Icons.search,
                          size: 40,
                          color: Colors.blue,
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Search for your boarding stop',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Use the search bar to find and select a nearby stop',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
