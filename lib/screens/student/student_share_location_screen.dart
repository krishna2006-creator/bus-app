import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:agni_college_bus_tracker/models/bus.dart';
import 'package:agni_college_bus_tracker/models/bus_location.dart';
import 'package:agni_college_bus_tracker/models/user.dart';
import 'package:agni_college_bus_tracker/services/location_service.dart';
import 'package:agni_college_bus_tracker/services/auth_service.dart';
import 'package:agni_college_bus_tracker/services/api_service.dart';
import 'package:agni_college_bus_tracker/config/app_config.dart';
import 'package:agni_college_bus_tracker/widgets/pop_scope.dart';

/// Student Location Sharing Screen
class StudentShareLocationScreen extends StatefulWidget {
  final Bus bus;

  const StudentShareLocationScreen({super.key, required this.bus});

  @override
  State<StudentShareLocationScreen> createState() =>
      _StudentShareLocationScreenState();
}

class _StudentShareLocationScreenState
    extends State<StudentShareLocationScreen> {
  final MapController _mapController = MapController();

  StreamSubscription<Position>? _positionSub;
  WebSocketChannel? _locationChannel;
  LatLng? _currentPos;
  bool _isSharing = false;
  bool _isManualRefreshing = false;
  int _updateCount = 0;
  double _accuracy = 0;
  double _speed = 0;
  String _statusMessage = 'Starting location sharing...';

  /// Auto-refresh timer ensures location updates every 5 seconds
  /// for efficient location sharing (changed from 1s to 5s)
  Timer? _autoRefreshTimer;

  @override
  void initState() {
    super.initState();
    if (widget.bus.busNumber.isEmpty) {
      _setStatus('Invalid bus number', isError: true);
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) context.pop();
      });
      return;
    }
    _startSharing();
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    _positionSub?.cancel();
    _locationChannel?.sink.close();
    super.dispose();
  }

  Future<void> _startSharing() async {
    try {
      final authService = context.read<AuthService>();
      final user = authService.currentUser;
      if (user == null) return;

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever ||
          permission == LocationPermission.denied) {
        if (mounted) {
          _setStatus('Location permission denied', isError: true);
          await Future.delayed(const Duration(seconds: 2));
          if (mounted) context.pop();
        }
        return;
      }

      setState(() {
        _isSharing = true;
        _statusMessage = 'Sharing location...';
      });

      await _setupLocationWebSocket();

      _positionSub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 0,
        ),
      ).listen((Position pos) {
        _updateLocationLocallyAndOnServer(pos);
      }, onError: (e) {
        debugPrint('Geolocator stream error: $e');
        _setStatus('Error: $e', isError: true);
      });

      /// Auto-refresh location every 5 seconds for efficient location sharing
      _startAutoRefresh();
    } catch (e) {
      debugPrint('Error in _startSharing: $e');
      _setStatus('Error: $e', isError: true);
    }
  }

  /// Auto-refresh location every 5 seconds for efficient location sharing
  void _startAutoRefresh() {
    _autoRefreshTimer?.cancel();
    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      if (!mounted || !_isSharing) return;
      try {
        final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
          ),
        );
        await _updateLocationLocallyAndOnServer(pos);
      } catch (e) {
        debugPrint('Auto-refresh location error: $e');
      }
    });
  }

  Future<void> _setupLocationWebSocket() async {
    final token = await ApiService.getToken();
    if (token == null) return;

    final uri = Uri.parse(
        '${AppConfig.wsUrl}/api/ws/location/${widget.bus.id}?token=$token');
    _locationChannel = WebSocketChannel.connect(uri);
  }

  Future<void> _updateLocationLocallyAndOnServer(Position pos) async {
    try {
      final authService = context.read<AuthService>();
      final user = authService.currentUser;
      final locService = context.read<LocationService>();
      if (user == null) return;

      final busLocation = BusLocation(
        busNumber: widget.bus.busNumber,
        latitude: pos.latitude,
        longitude: pos.longitude,
        speed: pos.speed * 3.6,
        timestamp: DateTime.now(),
        userType: UserRole.student,
        isSharedByStudent: true,
      );

      if (mounted) {
        setState(() {
          _currentPos = LatLng(pos.latitude, pos.longitude);
          _updateCount++;
          _accuracy = pos.accuracy;
          _speed = pos.speed * 3.6;
          _statusMessage = 'Location updated • $_updateCount updates';
        });
      }

      locService.updateLocation(busLocation);

      if (_locationChannel != null) {
        _locationChannel!.sink.add(json.encode({
          "type": "LOCATION_UPDATE",
          "bus_id": widget.bus.id,
          "latitude": pos.latitude,
          "longitude": pos.longitude,
          "speed": pos.speed * 3.6,
          "accuracy": pos.accuracy,
          "role": "student",
          "timestamp": DateTime.now().millisecondsSinceEpoch / 1000,
        }));
      }

      try {
        await ApiService.postPublicLocation(
          widget.bus.id,
          pos.latitude,
          pos.longitude,
          true,
          speed: pos.speed * 3.6,
        );
      } catch (e) {
        debugPrint('Error posting public location: $e');
      }

      if (mounted) {
        _mapController.move(LatLng(pos.latitude, pos.longitude), 16);
      }
    } catch (e) {
      debugPrint('Error in _updateLocationLocallyAndOnServer: $e');
    }
  }

  /// Stop sharing clears location from ALL sources!
  Future<void> _stopSharing() async {
    _positionSub?.cancel();
    _positionSub = null;
    _autoRefreshTimer?.cancel();

    if (_locationChannel != null) {
      try {
        _locationChannel!.sink.add(json.encode({
          "type": "STOP_SHARING",
          "bus_id": widget.bus.id,
          "role": "student",
        }));
      } catch (_) {}
      _locationChannel!.sink.close();
      _locationChannel = null;
    }

    context.read<LocationService>().removeLocation(widget.bus.busNumber);
    ApiService.clearPublicLocation(widget.bus.id);

    if (mounted) {
      setState(() {
        _isSharing = false;
        _statusMessage = 'Sharing stopped';
      });
      context.pop();
    }
  }

  void _setStatus(String message, {bool isError = false}) {
    if (mounted) {
      setState(() => _statusMessage = message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppPopScope(
      canPop: !_isSharing,
      onPopInvokedWithResult: (didPop, result) async {
        if (!didPop && _isSharing) await _stopSharing();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Share Your Location'),
          centerTitle: true,
          backgroundColor: Colors.blue,
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        body: Column(
          children: [
            // Status Card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _isSharing ? Colors.blue.shade50 : Colors.orange.shade50,
                border: Border(
                  bottom: BorderSide(
                    color: _isSharing ? Colors.blue : Colors.orange,
                    width: 3,
                  ),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: _isSharing ? Colors.blue : Colors.orange,
                          borderRadius: BorderRadius.circular(50),
                        ),
                        child: Icon(
                          _isSharing ? Icons.location_on : Icons.location_off,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Bus ${widget.bus.busNumber} • Location Sharing',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              _statusMessage,
                              style: TextStyle(
                                fontSize: 11,
                                color: _isSharing
                                    ? Colors.blue.shade700
                                    : Colors.orange.shade700,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (_currentPos != null) ...[
                    const SizedBox(height: 12),
                    Divider(color: Colors.grey.shade300),
                    const SizedBox(height: 12),
                    _buildInfoRow(
                        'Latitude', _currentPos!.latitude.toStringAsFixed(5)),
                    _buildInfoRow(
                        'Longitude', _currentPos!.longitude.toStringAsFixed(5)),
                    _buildInfoRow('Speed', '${_speed.toStringAsFixed(1)} km/h'),
                    _buildInfoRow(
                        'Accuracy', '${_accuracy.toStringAsFixed(1)} m'),
                  ],
                ],
              ),
            ),
            // Map
            Expanded(
              child: _currentPos != null
                  ? FlutterMap(
                      mapController: _mapController,
                      options: MapOptions(
                        initialCenter: _currentPos!,
                        initialZoom: 16,
                      ),
                      children: [
                        TileLayer(
                          urlTemplate:
                              'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                          userAgentPackageName: 'com.busappvictory.app',
                        ),
                        MarkerLayer(
                          markers: [
                            Marker(
                              point: _currentPos!,
                              child: const Icon(Icons.person_pin_circle,
                                  color: Colors.blue, size: 40),
                            ),
                            const Marker(
                              point: LatLng(
                                AppConfig.collegeLatitude,
                                AppConfig.collegeLongitude,
                              ),
                              child: Icon(Icons.school,
                                  color: Colors.red, size: 40),
                            ),
                          ],
                        ),
                      ],
                    )
                  : Container(
                      color: Colors.grey.shade200,
                      child: const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            CircularProgressIndicator(),
                            SizedBox(height: 16),
                            Text('Getting your location...'),
                          ],
                        ),
                      ),
                    ),
            ),
            // Action Buttons
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border(
                  top: BorderSide(color: Colors.grey.shade200, width: 1),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _isManualRefreshing ? null : _manualRefresh,
                      icon: const Icon(Icons.refresh, size: 18),
                      label: const Text('Refresh'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue.shade600,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _isSharing ? _stopSharing : null,
                      icon: const Icon(Icons.stop, size: 18),
                      label: const Text('Stop'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red.shade600,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _manualRefresh() async {
    if (_isManualRefreshing) return;
    setState(() => _isManualRefreshing = true);
    try {
      Position pos = await Geolocator.getCurrentPosition(
        locationSettings:
            const LocationSettings(accuracy: LocationAccuracy.high),
      );
      await _updateLocationLocallyAndOnServer(pos);
      _setStatus('Location refreshed');
    } catch (e) {
      _setStatus('Refresh failed: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isManualRefreshing = false);
    }
  }
}

Widget _buildInfoRow(String label, String value) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    ),
  );
}
