import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:go_router/go_router.dart';
import '../../services/api_service.dart';

class OpenStreetMapScreen extends StatefulWidget {
  final double latitude;
  final double longitude;
  final double speed;
  final String title;
  final int? busId;
  final LatLng? initialPickupLocation;

  const OpenStreetMapScreen({
    super.key,
    // Default coordinates (Update these to your college location)
    this.latitude = 12.9716,
    this.longitude = 77.5946,
    this.speed = 0.0,
    this.title = 'Live Location',
    this.busId,
    this.initialPickupLocation,
  });

  @override
  State<OpenStreetMapScreen> createState() => _OpenStreetMapScreenState();
}

class _OpenStreetMapScreenState extends State<OpenStreetMapScreen>
    with SingleTickerProviderStateMixin {
  final MapController _mapController = MapController();

  late AnimationController _animationController;
  late LatLng _currentBusPosition;
  late LatLng _startPosition;
  late LatLng _endPosition;

  // User selected pickup location
  LatLng? _userPickupLocation;
  bool _hasReachedPickup = false;
  bool _isSelectingPickup = true; // Track if user is in selection mode

  // Agni College of Technology, Thalambur, Chennai
  final LatLng _collegeLocation = const LatLng(12.8482, 80.1943);

  @override
  void initState() {
    super.initState();
    _currentBusPosition = LatLng(widget.latitude, widget.longitude);
    _startPosition = _currentBusPosition;
    _endPosition = _currentBusPosition;

    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..addListener(() {
        setState(() {
          final t = _animationController.value;
          _currentBusPosition = LatLng(
            _startPosition.latitude +
                (_endPosition.latitude - _startPosition.latitude) * t,
            _startPosition.longitude +
                (_endPosition.longitude - _startPosition.longitude) * t,
          );
        });
      });

    if (widget.initialPickupLocation != null) {
      _userPickupLocation = widget.initialPickupLocation;
      _isSelectingPickup = false; // Already has a location
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(OpenStreetMapScreen oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.latitude != oldWidget.latitude ||
        widget.longitude != oldWidget.longitude) {
      _startPosition = _currentBusPosition;
      _endPosition = LatLng(widget.latitude, widget.longitude);
      _animationController.forward(from: 0.0);
    }

    // Check if bus has reached pickup whenever location updates
    if (_userPickupLocation != null && !_hasReachedPickup) {
      final busLocation = LatLng(widget.latitude, widget.longitude);
      final distance = const Distance()
          .as(LengthUnit.Meter, busLocation, _userPickupLocation!);

      // If within 200 meters, consider it reached
      if (distance < 200) {
        setState(() {
          _hasReachedPickup = true;
        });
      }
    }
  }

  // Toggle tracking mode manually if needed (e.g. user boarded)
  void _toggleTrackingMode() {
    setState(() {
      _hasReachedPickup = !_hasReachedPickup;
    });
  }

  Future<void> _savePickupLocation() async {
    if (_userPickupLocation == null || widget.busId == null) return;
    // In a real app, you might get the center of the map here if using "center pin" selection

    final success = await ApiService.pinBus(
      widget.busId!,
      _userPickupLocation!.latitude,
      _userPickupLocation!.longitude,
    );

    if (!mounted) return;

    if (success) {
      setState(() {
        _isSelectingPickup = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              "Pickup point set! You'll be notified when Bus ${widget.busId} starts."),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 2),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Failed to save pickup location. Please try again."),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _removePickupLocation() async {
    if (widget.busId == null) return;

    // Call the API to remove the pin from the backend
    final success = await ApiService.unpinBus(widget.busId!);

    if (!mounted) return;

    // We clear the local state if the API call was successful
    // or if we want to allow clearing a selection that hasn't been saved yet (optional improvement)
    if (success) {
      setState(() {
        _userPickupLocation = null;
        _hasReachedPickup = false;
        _isSelectingPickup = true; // Go back to selection mode
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Pickup point removed.")),
      );
    } else {
      // If it failed, it might be because it didn't exist on the server (404).
      // In a real app, you might check for 404 specifically.
      // For now, we'll assume if it fails, we shouldn't clear the UI unless we are sure.
      // However, to be user-friendly, if the user wants to clear the map, we often just clear it.
      // Let's stick to API success confirmation for safety.
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Could not remove pin (or no pin existed)."),
          backgroundColor: Colors.red,
        ),
      );

      // Fallback: If you want to force clear local state even on error:
      // setState(() { _userPickupLocation = null; });
    }
  }

  void _fitBounds() {
    final busLocation = _currentBusPosition;

    // Target is either pickup or college depending on state
    final target = _hasReachedPickup ? _collegeLocation : _userPickupLocation;

    if (target != null) {
      final bounds = LatLngBounds.fromPoints([
        busLocation,
        target,
      ]);

      _mapController.fitCamera(
        CameraFit.bounds(
          bounds: bounds,
          padding: const EdgeInsets.only(
            top: 50.0,
            left: 50.0,
            right: 50.0,
            bottom: 220.0, // Adjust for the bottom card
          ),
        ),
      );
    } else {
      _mapController.move(busLocation, 15.0);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: LatLng(widget.latitude, widget.longitude),
              initialZoom: 15.0,
              onTap: (tapPosition, point) {
                if (_isSelectingPickup) {
                  setState(() {
                    _userPickupLocation = point;
                    _hasReachedPickup = false; // Reset when new point selected
                  });
                }
              },
            ),
            children: [
              TileLayer(
                // OpenStreetMap standard tile server
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                // It's good practice to identify your app
                userAgentPackageName: 'com.busappvictory.app',
              ),
              PolylineLayer(
                polylines: [
                  if (_userPickupLocation != null &&
                      _currentBusPosition.latitude != 0)
                    Polyline(
                      points: [
                        _currentBusPosition,
                        // Dynamic routing: Switch destination based on state
                        _hasReachedPickup
                            ? _collegeLocation
                            : _userPickupLocation!,
                      ],
                      // Green line for "On Board", Blue for "Waiting"
                      color:
                          _hasReachedPickup ? Colors.green : Colors.blueAccent,
                      strokeWidth: 4.0,
                      isDotted: !_hasReachedPickup, // Dotted line while waiting
                    ),
                ],
              ),
              MarkerLayer(
                markers: [
                  // Bus Marker
                  Marker(
                    point: _currentBusPosition,
                    width: 50,
                    height: 50,
                    // Use the custom bus marker icon as required
                    child: const Icon(
                      Icons.directions_bus,
                      color: Colors.indigo,
                      size: 32,
                    ),
                  ),
                  // User Pickup Marker
                  if (_userPickupLocation != null)
                    Marker(
                      point: _userPickupLocation!,
                      width: 40,
                      height: 40,
                      child: const Icon(Icons.location_on,
                          color: Colors.orange, size: 40),
                    ),
                  // College Marker
                  Marker(
                    point: _collegeLocation,
                    width: 40,
                    height: 40,
                    child:
                        const Icon(Icons.school, color: Colors.red, size: 40),
                  ),
                ],
              ),
            ],
          ),
          // Google Maps Style Search Bar (Visible only during selection)
          if (_isSelectingPickup)
            Positioned(
              top: 50,
              left: 16,
              right: 16,
              child: _buildSearchBar(),
            ),
          // Recenter Button
          Positioned(
            top: _isSelectingPickup ? 120 : 50, // Adjust based on search bar
            right: 20,
            child: FloatingActionButton(
              heroTag: "recenter_btn",
              onPressed: _fitBounds,
              backgroundColor: Colors.white,
              mini: true,
              child: const Icon(Icons.center_focus_strong, color: Colors.blue),
            ),
          ),
          // Bottom Sheet / Status Card
          Positioned(
            bottom: 20,
            left: 20,
            right: 20,
            child: StopPredictionWidget(
              busLocation: _currentBusPosition,
              busSpeed: widget.speed,
              userPickupLocation: _userPickupLocation,
              collegeLocation: _collegeLocation,
              hasReachedPickup: _hasReachedPickup,
              isSelecting: _isSelectingPickup,
              busId: widget.busId,
              onSavePickup: _savePickupLocation,
              onTogglePhase: _toggleTrackingMode,
              onRemovePickup: _removePickupLocation,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            const Icon(Icons.search, color: Colors.black54),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _userPickupLocation == null
                    ? "Search pickup stop..."
                    : "Location selected",
                style: TextStyle(
                  color: _userPickupLocation == null
                      ? Colors.black38
                      : Colors.black87,
                  fontSize: 16,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class StopPredictionWidget extends StatelessWidget {
  final LatLng busLocation;
  final double busSpeed;
  final LatLng? userPickupLocation;
  final LatLng collegeLocation;
  final bool hasReachedPickup;
  final bool isSelecting;
  final int? busId;
  final VoidCallback? onSavePickup;
  final VoidCallback? onTogglePhase;
  final VoidCallback? onRemovePickup;

  const StopPredictionWidget({
    super.key,
    required this.busLocation,
    required this.busSpeed,
    required this.userPickupLocation,
    required this.collegeLocation,
    required this.hasReachedPickup,
    required this.isSelecting,
    this.busId,
    this.onSavePickup,
    this.onTogglePhase,
    this.onRemovePickup,
  });

  @override
  Widget build(BuildContext context) {
    // Phase 1: Selection Mode UI
    if (isSelecting) {
      return SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: userPickupLocation != null ? onSavePickup : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            elevation: 4,
          ),
          child: const Text(
            "CONFIRM PICKUP",
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ),
      );
    }

    // Phase 2 & 3: Tracking Mode UI (Uber Style Bottom Sheet)
    return Card(
      elevation: 8,
      margin: EdgeInsets.zero,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
            top: Radius.circular(20), bottom: Radius.circular(20)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 20.0, horizontal: 20.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag Handle
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            _buildPredictionText(),
            const SizedBox(height: 20),
            // Action Buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed:
                        onRemovePickup, // This will reset to selection mode
                    icon: const Icon(Icons.edit_location_alt),
                    label: const Text("Change Stop"),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            // Debug/Manual toggle for testing the flow
            if (kDebugMode && userPickupLocation != null)
              TextButton(
                onPressed: onTogglePhase,
                child: Text(
                  hasReachedPickup ? "Show Pickup View" : "I have boarded",
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPredictionText() {
    final targetLocation =
        hasReachedPickup ? collegeLocation : userPickupLocation!;
    final distance =
        Distance().as(LengthUnit.Kilometer, busLocation, targetLocation);
    // Assuming average speed of 30 km/h
    // We use a correction factor of 1.3 for road curvature vs straight line
    final roadDistance = distance * 1.3;
    final timeInMinutes = (roadDistance / 30 * 60).round();

    // Calculate estimated arrival time
    final arrivalTime = DateTime.now().add(Duration(minutes: timeInMinutes));
    final hour = arrivalTime.hour > 12
        ? arrivalTime.hour - 12
        : (arrivalTime.hour == 0 ? 12 : arrivalTime.hour);
    final minute = arrivalTime.minute.toString().padLeft(2, '0');
    final period = arrivalTime.hour >= 12 ? 'PM' : 'AM';
    final formattedTime = "$hour:$minute $period";

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hasReachedPickup ? "Heading to College" : "Bus Arriving",
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  hasReachedPickup ? "Trip in progress" : "at your pickup stop",
                  style: const TextStyle(fontSize: 14, color: Colors.grey),
                ),
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  "$timeInMinutes min",
                  style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.green),
                ),
                Text(
                  formattedTime,
                  style: const TextStyle(fontSize: 14, color: Colors.grey),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 16),
        _buildTrafficIndicator(),
      ],
    );
  }

  Widget _buildTrafficIndicator() {
    String status;
    Color color;
    IconData icon;

    if (busSpeed <= 5) {
      status = "Heavy Traffic / Stopped";
      color = Colors.red;
      icon = Icons.traffic;
    } else if (busSpeed <= 25) {
      status = "Moderate Traffic";
      color = Colors.orange;
      icon = Icons.directions_car;
    } else {
      status = "Low Traffic";
      color = Colors.green;
      icon = Icons.speed;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 8),
              Text(
                status,
                style: TextStyle(
                    color: color, fontWeight: FontWeight.w600, fontSize: 14),
              ),
            ],
          ),
          Text(
            "${busSpeed.toStringAsFixed(1)} km/h",
            style: const TextStyle(
                color: Colors.black54, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}
