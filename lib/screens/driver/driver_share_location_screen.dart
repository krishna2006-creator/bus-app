import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:agni_college_bus_tracker/models/bus_location.dart';
import 'package:agni_college_bus_tracker/models/user.dart';
import 'package:agni_college_bus_tracker/services/location_service.dart';
import 'package:agni_college_bus_tracker/services/auth_service.dart';
import 'package:agni_college_bus_tracker/services/api_service.dart';
import 'package:agni_college_bus_tracker/config/app_config.dart';
import 'package:agni_college_bus_tracker/widgets/pop_scope.dart';

class DriverShareLocationScreen extends StatefulWidget {
  const DriverShareLocationScreen({super.key});

  @override
  State<DriverShareLocationScreen> createState() =>
      _DriverShareLocationScreenState();
}

class _DriverShareLocationScreenState extends State<DriverShareLocationScreen> {
  final Completer<GoogleMapController> _mapController = Completer();

  StreamSubscription<Position>? _positionSub;
  WebSocketChannel? _locationChannel;
  CameraPosition? _currentPos;
  String? _busNumber;
  bool _isSharing = false;
  int _updateCount = 0;
  double _accuracy = 0;
  double _speed = 0;
  String _statusMessage = 'Initializing...';

  @override
  void initState() {
    super.initState();
    _startSharing();
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _locationChannel?.sink.close();
    super.dispose();
  }

  Future<void> _startSharing() async {
    final authService = context.read<AuthService>();
    final user = authService.currentUser;
    if (user == null) {
      if (mounted) context.pop();
      return;
    }

    _busNumber = user.assignedBusNumber;

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever ||
        permission == LocationPermission.denied) {
      if (mounted) {
        _setStatus('Location permission required', isError: true);
        await Future.delayed(Duration(seconds: 2));
        if (mounted) context.pop();
      }
      return;
    }

    final pos = await Geolocator.getCurrentPosition(
      locationSettings: LocationSettings(accuracy: LocationAccuracy.high),
    );

    if (mounted) {
      setState(() {
        _currentPos = CameraPosition(
          target: LatLng(pos.latitude, pos.longitude),
          zoom: 16,
        );
        _isSharing = true;
        _statusMessage = 'Sharing live location...';
      });
    }

    await _connectWebSocket();

    _positionSub = Geolocator.getPositionStream(
      locationSettings: LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 0,
      ),
    ).listen((Position pos) {
      _updateLocation(pos);
      _sendViaWebSocket(pos);
    }, onError: (e) {
      debugPrint('Geolocator stream error: $e');
      _setStatus('Error: $e', isError: true);
    });
  }

  Future<void> _connectWebSocket() async {
    if (_busNumber == null) return;
    final token = await ApiService.getToken();
    if (token == null) return;
    try {
      final uri = Uri.parse(
          '${AppConfig.wsUrl}/api/ws/location/$_busNumber?token=$token');
      _locationChannel = WebSocketChannel.connect(uri);
    } catch (e) {
      debugPrint('WebSocket connect error: $e');
    }
  }

  void _sendViaWebSocket(Position pos) {
    if (_locationChannel?.sink == null) return;
    try {
      _locationChannel!.sink.add(json.encode({
        'type': 'LOCATION_UPDATE',
        'bus_id': _busNumber,
        'latitude': pos.latitude,
        'longitude': pos.longitude,
        'speed': pos.speed * 3.6,
        'role': 'driver',
        'timestamp': DateTime.now().toIso8601String(),
      }));
    } catch (e) {
      debugPrint('WS send error: $e');
    }
  }

  Future<void> _updateLocation(Position pos) async {
    if (!mounted) return;
    final locService = context.read<LocationService>();
    final busLoc = BusLocation(
      busNumber: _busNumber ?? '',
      latitude: pos.latitude,
      longitude: pos.longitude,
      speed: pos.speed * 3.6,
      timestamp: DateTime.now(),
      userType: UserRole.driver,
      isSharedByStudent: false,
    );
    locService.updateLocation(busLoc);
    setState(() {
      _updateCount++;
      _accuracy = pos.accuracy;
      _speed = pos.speed * 3.6;
      _statusMessage = 'Updated - $_updateCount snaps';
    });
    try {
      final busId = int.tryParse(_busNumber ?? '');
      if (busId != null) {
        await ApiService.postPublicLocation(
            busId, pos.latitude, pos.longitude, true,
            speed: pos.speed * 3.6);
      }
    } catch (_) {}
  }

  Future<void> _stopSharing() async {
    // Capture services before async operations
    final locService = context.read<LocationService>();
    final busNumber = _busNumber;

    // Immediately stop position stream for instant response
    await _positionSub?.cancel();
    _positionSub = null;

    // Send STOP signal and close WebSocket immediately
    if (_locationChannel?.sink != null) {
      try {
        _locationChannel!.sink.add(json.encode({
          'type': 'STOP_SHARING',
          'bus_id': busNumber,
          'role': 'driver',
        }));
      } catch (_) {}
      _locationChannel!.sink.close();
      _locationChannel = null;
    }

    // Remove location and pop in background
    if (busNumber != null) {
      locService.removeLocation(busNumber);
      final busId = int.tryParse(busNumber);
      if (busId != null) {
        ApiService.clearPublicLocation(busId); // fire-and-forget
      }
    }

    if (mounted) {
      setState(() {
        _isSharing = false;
        _statusMessage = 'Sharing stopped';
      });
      context.pop(); // Pop immediately, no delay
    }
  }

  void _setStatus(String message, {bool isError = false}) {
    if (mounted) setState(() => _statusMessage = message);
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
          title: Text('Share Bus $_busNumber'),
          centerTitle: true,
          backgroundColor: Colors.blue,
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        body: Column(
          children: [
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(12),
              color: _isSharing ? Colors.blue.shade50 : Colors.orange.shade50,
              child: Row(
                children: [
                  Icon(
                    _isSharing ? Icons.location_on : Icons.location_off,
                    color: _isSharing ? Colors.blue : Colors.orange,
                    size: 28,
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Bus $_busNumber',
                            style: TextStyle(fontWeight: FontWeight.bold)),
                        Text(_statusMessage,
                            style: TextStyle(
                                fontSize: 12, color: Colors.grey.shade700)),
                      ],
                    ),
                  ),
                  if (_isSharing)
                    Container(
                      padding: EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.green,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Icon(Icons.check, color: Colors.white, size: 16),
                    ),
                ],
              ),
            ),
            Expanded(
              child: _currentPos != null
                  ? GoogleMap(
                      mapType: MapType.normal,
                      initialCameraPosition: _currentPos!,
                      onMapCreated: (ctrl) => _mapController.complete(ctrl),
                      myLocationEnabled: true,
                      myLocationButtonEnabled: true,
                      markers: {
                        if (_currentPos != null)
                          Marker(
                            markerId: MarkerId('driver'),
                            position: _currentPos!.target,
                            icon: BitmapDescriptor.defaultMarkerWithHue(
                                BitmapDescriptor.hueBlue),
                            infoWindow: InfoWindow(title: 'Bus $_busNumber'),
                          ),
                      },
                    )
                  : Center(child: CircularProgressIndicator()),
            ),
            if (_isSharing && _currentPos != null)
              Container(
                padding: EdgeInsets.all(12),
                color: Colors.black87,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _infoCol('Speed', '${_speed.toStringAsFixed(1)} km/h'),
                    _infoCol('Updates', '$_updateCount'),
                    _infoCol('Accuracy', '±${_accuracy.toStringAsFixed(0)}m'),
                  ],
                ),
              ),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isSharing ? _stopSharing : null,
                  icon: Icon(Icons.stop_circle),
                  label: Text('STOP SHARING'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(vertical: 14),
                    textStyle:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoCol(String label, String value) {
    return Column(
      children: [
        Text(label,
            style: TextStyle(color: Colors.grey.shade400, fontSize: 11)),
        Text(value,
            style: TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.bold)),
      ],
    );
  }
}
