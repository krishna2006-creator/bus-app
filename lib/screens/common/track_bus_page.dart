import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:agni_college_bus_tracker/models/bus.dart';
import 'package:agni_college_bus_tracker/config/app_config.dart';
import 'package:agni_college_bus_tracker/services/location_service.dart';
import 'package:agni_college_bus_tracker/services/api_service.dart';

class TrackBusPage extends StatefulWidget {
  final Bus bus;
  const TrackBusPage({super.key, required this.bus});

  @override
  State<TrackBusPage> createState() => _TrackBusPageState();
}

class _TrackBusPageState extends State<TrackBusPage> {
  final MapController _mapController = MapController();
  WebSocketChannel? _channel;
  Timer? _reconnectTimer;
  Timer? _fallbackTimer;
  Timer? _backendPollTimer;

  // Live Location and Routing State
  LatLng? _busLocation;
  double _speed = 0.0;
  List<LatLng> _routePoints = [];
  double _distanceKm = 0.0;
  int _etaMinutes = 0;
  bool _isOffline = true;

  // College coordinates (Final destination)
  static const LatLng _collegeLocation = LatLng(
    AppConfig.collegeLatitude,
    AppConfig.collegeLongitude,
  );

  @override
  void initState() {
    super.initState();
    _initializeState();
    _connectWebSocket();
    _startFallbackSync();
    _startBackendPolling();
  }

  @override
  void dispose() {
    _channel?.sink.close();
    _reconnectTimer?.cancel();
    _fallbackTimer?.cancel();
    _backendPollTimer?.cancel();
    super.dispose();
  }

  void _initializeState() {
    final locService = context.read<LocationService>();
    final loc = locService.getBestLocationForBus(widget.bus.busNumber);
    if (loc != null) {
      final pos = LatLng(loc.latitude, loc.longitude);
      _busLocation = pos;
      _speed = loc.speed;
      _isOffline = false;
      _fetchOSRMRouting(pos, _collegeLocation);
    }
  }

  void _startFallbackSync() {
    _fallbackTimer = Timer.periodic(const Duration(seconds: 15), (timer) {
      final locService = context.read<LocationService>();
      final loc = locService.getBestLocationForBus(widget.bus.busNumber);
      if (loc != null) {
        final pos = LatLng(loc.latitude, loc.longitude);
        if (_busLocation == null ||
            _busLocation!.latitude != pos.latitude ||
            _busLocation!.longitude != pos.longitude) {
          if (mounted) {
            setState(() {
              _busLocation = pos;
              _speed = loc.speed;
              _isOffline = false;
            });
            _fetchOSRMRouting(pos, _collegeLocation);
          }
        }
      }
    });
  }

  void _startBackendPolling() {
    _backendPollTimer?.cancel();
    _backendPollTimer = Timer.periodic(const Duration(seconds: 8), (_) async {
      if (!mounted) return;
      await _refreshFromBackend();
    });
    unawaited(_refreshFromBackend());
  }

  Future<void> _refreshFromBackend() async {
    try {
      final result = await ApiService.getBusLocation(widget.bus.id);
      if (!mounted || result == null) return;

      final lat = (result['latitude'] as num?)?.toDouble();
      final lng = (result['longitude'] as num?)?.toDouble();
      if (lat == null || lng == null) return;

      final pos = LatLng(lat, lng);
      final spd = (result['speed'] as num?)?.toDouble() ?? 0.0;

      if (_busLocation == null ||
          (_busLocation!.latitude - lat).abs() > 0.00001 ||
          (_busLocation!.longitude - lng).abs() > 0.00001 ||
          _speed != spd) {
        if (mounted) {
          setState(() {
            _busLocation = pos;
            _speed = spd;
            _isOffline = false;
          });
          _fetchOSRMRouting(pos, _collegeLocation);
        }
      }
    } catch (e) {
      debugPrint('Backend polling failed: $e');
    }
  }

  Future<void> _connectWebSocket() async {
    try {
      final token = await ApiService.getToken();
      final wsUrl = token != null
          ? '${AppConfig.wsUrl}/api/ws/location/${widget.bus.id}?token=$token'
          : '${AppConfig.wsUrl}/api/ws/location/${widget.bus.id}';

      _channel = WebSocketChannel.connect(Uri.parse(wsUrl));
      _channel!.stream.listen((message) {
        if (!mounted) return;
        final data = jsonDecode(message);
        final type = data['type'];
        final payload = data['payload'] ?? data['data'] ?? data;
        final busIdStr =
            payload['bus_id']?.toString() ?? data['bus_id']?.toString();

        if (busIdStr != widget.bus.id.toString() &&
            busIdStr != widget.bus.busNumber) {
          return;
        }

        if (type == 'LOCATION_UPDATE' || type == 'LAST_KNOWN_LOCATION') {
          final lat = (payload['latitude'] as num?)?.toDouble() ?? 0.0;
          final lng = (payload['longitude'] as num?)?.toDouble() ?? 0.0;
          final spd = (payload['speed'] as num?)?.toDouble() ?? 0.0;

          if (lat == 0.0 && lng == 0.0) {
            setState(() {
              _isOffline = true;
            });
            return;
          }

          final newPos = LatLng(lat, lng);
          setState(() {
            _busLocation = newPos;
            _speed = spd;
            _isOffline = false;
          });

          _fetchOSRMRouting(newPos, _collegeLocation);

          try {
            _mapController.move(newPos, _mapController.camera.zoom);
          } catch (_) {}
        } else if (type == 'LOCATION_CLEARED') {
          setState(() {
            _isOffline = true;
          });
        }
      }, onError: (e) {
        debugPrint("WS Error: $e");
        _scheduleReconnect();
      }, onDone: () {
        _scheduleReconnect();
      });
    } catch (e) {
      debugPrint("WebSocket initialization failed: $e");
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) _connectWebSocket();
    });
  }

  Future<void> _fetchOSRMRouting(LatLng start, LatLng end) async {
    final url =
        'https://router.project-osrm.org/route/v1/driving/${start.longitude},${start.latitude};${end.longitude},${end.latitude}?overview=full&geometries=geojson';
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['routes'] == null || data['routes'].isEmpty) return;

        final route = data['routes'][0];
        final geometry = route['geometry']['coordinates'] as List;

        if (mounted) {
          setState(() {
            _routePoints = geometry
                .map((p) => LatLng(p[1].toDouble(), p[0].toDouble()))
                .toList();
            _distanceKm = double.parse(route['distance'].toString()) / 1000.0;
            _etaMinutes =
                (double.parse(route['duration'].toString()) / 60).round();
          });
        }
      }
    } catch (e) {
      debugPrint("OSRM Routing Error: $e");
    }
  }

  void _recenter() {
    if (_busLocation != null) {
      _mapController.move(_busLocation!, 15);
    }
  }

  Future<void> _callDriver() async {
    final phone = widget.bus.driverPhone;
    if (phone != null && phone.isNotEmpty) {
      final url = Uri.parse('tel:$phone');
      if (await canLaunchUrl(url)) {
        await launchUrl(url);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not initiate call')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final initialCenter = _busLocation ?? _collegeLocation;
    final arrivalTime = DateTime.now().add(Duration(minutes: _etaMinutes));
    final arrivalStr =
        "${arrivalTime.hour.toString().padLeft(2, '0')}:${arrivalTime.minute.toString().padLeft(2, '0')}";

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        title: Text('Live Tracking - Bus ${widget.bus.busNumber}'),
        actions: [
          if (_busLocation != null)
            IconButton(
              icon: const Icon(Icons.my_location),
              onPressed: _recenter,
            ),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: initialCenter,
              initialZoom: 14.5,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.busappvictory.app',
              ),
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: _routePoints,
                    strokeWidth: 6.0,
                    color: Colors.blue.shade600,
                  ),
                ],
              ),
              MarkerLayer(
                markers: [
                  // College destination marker
                  const Marker(
                    point: _collegeLocation,
                    width: 50,
                    height: 50,
                    child: Icon(
                      Icons.school_rounded,
                      color: Colors.redAccent,
                      size: 40,
                    ),
                  ),
                  // Bus live marker
                  if (_busLocation != null)
                    Marker(
                      point: _busLocation!,
                      width: 55,
                      height: 55,
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.white,
                            width: 3.0,
                          ),
                          boxShadow: const [
                            BoxShadow(
                              color: Colors.black26,
                              blurRadius: 6,
                              offset: Offset(0, 3),
                            ),
                          ],
                        ),
                        child: CircleAvatar(
                          backgroundColor: Colors.blue.shade50,
                          backgroundImage: const AssetImage('assets/dog.png'),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),

          // Speedometer floating badge
          if (!_isOffline)
            Positioned(
              left: 16,
              top: 16,
              child: Card(
                elevation: 6,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(100),
                ),
                color: Colors.black.withValues(alpha: 0.8),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.speed_rounded,
                        color: Colors.greenAccent,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${_speed.toStringAsFixed(0)} km/h',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // Live indicator
          Positioned(
            right: 16,
            top: 16,
            child: Card(
              elevation: 4,
              color: _isOffline ? Colors.orange : Colors.green,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _isOffline ? 'OFFLINE' : 'LIVE',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Bottom Uber/Zomato style floating direction card
          Positioned(
            left: 16,
            right: 16,
            bottom: 16,
            child: Card(
              elevation: 12,
              shadowColor: Colors.black45,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Upper green banner
                  Container(
                    width: double.infinity,
                    padding:
                        const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                    decoration: const BoxDecoration(
                      color: Color(0xFF1E3A8A), // Deep Google Maps Blue
                      borderRadius:
                          BorderRadius.vertical(top: Radius.circular(16)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _isOffline ? 'BUS OFFLINE' : 'ROUTE TO AGNI COLLEGE',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.0,
                          ),
                        ),
                        if (!_isOffline)
                          const Text(
                            'GPS ACTIVE',
                            style: TextStyle(
                              color: Colors.greenAccent,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                      ],
                    ),
                  ),

                  // Middle duration/distance section
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      _isOffline
                                          ? '-- min'
                                          : '$_etaMinutes min',
                                      style: TextStyle(
                                        fontSize: 26,
                                        fontWeight: FontWeight.bold,
                                        color: _isOffline
                                            ? Colors.grey
                                            : Colors.green.shade600,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    const Icon(
                                      Icons.directions_bus_rounded,
                                      color: Colors.grey,
                                      size: 20,
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _isOffline
                                      ? 'Distance unavailable'
                                      : '${_distanceKm.toStringAsFixed(1)} km • Arriving at $arrivalStr',
                                  style: TextStyle(
                                    color: Colors.grey.shade600,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.blue.shade50,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                'Route ${widget.bus.route}',
                                style: TextStyle(
                                  color: Colors.blue.shade800,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const Divider(height: 24),

                        // Driver contact and call section
                        Row(
                          children: [
                            CircleAvatar(
                              backgroundColor: Colors.grey.shade200,
                              child: Icon(Icons.person,
                                  color: Colors.grey.shade700),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    widget.bus.driverName ??
                                        'No assigned driver',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  ),
                                  Text(
                                    widget.bus.driverPhone ??
                                        'Contact not available',
                                    style: TextStyle(
                                      color: Colors.grey.shade600,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (widget.bus.driverPhone != null &&
                                widget.bus.driverPhone!.isNotEmpty)
                              IconButton.filled(
                                onPressed: _callDriver,
                                icon: const Icon(Icons.call),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
