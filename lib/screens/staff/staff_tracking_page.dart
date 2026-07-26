import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:agni_college_bus_tracker/models/bus.dart';
import 'package:provider/provider.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:agni_college_bus_tracker/services/api_service.dart';
import 'package:agni_college_bus_tracker/services/notification_service.dart';
import 'package:agni_college_bus_tracker/config/app_config.dart';
import 'package:go_router/go_router.dart';
import 'dart:convert';

class StaffTrackingPage extends StatefulWidget {
  final Bus bus;
  const StaffTrackingPage({super.key, required this.bus});

  @override
  State<StaffTrackingPage> createState() => _StaffTrackingPageState();
}

class _StaffTrackingPageState extends State<StaffTrackingPage> {
  final MapController _mapController = MapController();
  final Map<String, LatLng> _busPositions = {};
  WebSocketChannel? _locationChannel;
  String _status = "Waiting for bus location...";
  double _eta = 0;
  StreamSubscription? _notifSubscription;
  StreamSubscription? _locationSubscription;
  int _updateCount = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _setupLocationWebSocket();
      _setupNotificationListener();
    });
  }

  Future<void> _setupLocationWebSocket() async {
    final token = await ApiService.getToken();
    if (token == null) {
      debugPrint("No auth token for location WebSocket");
      return;
    }

    final uri = Uri.parse(
        '${AppConfig.wsUrl}/api/ws/location/${widget.bus.id}?token=$token');

    _locationChannel = WebSocketChannel.connect(uri);
    _locationSubscription = _locationChannel!.stream.listen(
        _handleLocationMessage,
        onError: (error) => debugPrint("Location WS Error: $error"),
        onDone: () => debugPrint("Location WS Done"));
  }

  void _setupNotificationListener() {
    final notifService = context.read<NotificationService>();

    _notifSubscription = notifService.messages.listen((message) {
      if (!mounted) return;

      // Handle general notifications if needed, but not location updates
      // Location updates are now handled by _locationChannel
    });
  }

  void _handleLocationMessage(dynamic message) {
    if (!mounted) return;
    debugPrint(
        "StaffTrackingPage received WS message: $message"); // Added debug print
    try {
      final data = json.decode(message);
      final type = data['type'];
      final payload = data['data'] ??
          data['payload']; // 'data' for manager, 'payload' for analyzer
      final busId = data['bus_id'];

      if (busId != widget.bus.id) return; // Ensure it's for the current bus

      setState(() {
        if (type == 'LOCATION_UPDATE' || type == 'LAST_KNOWN_LOCATION') {
          final lat = (payload['latitude'] as num?)?.toDouble() ?? 0.0;
          final lng = (payload['longitude'] as num?)?.toDouble() ?? 0.0;
          final senderId = (payload['user_id'] ?? 'unknown').toString();

          if (lat == 0 && lng == 0) {
            // Signal to clear marker
            _busPositions.remove(senderId);
          } else {
            _busPositions[senderId] = LatLng(lat, lng);
            if (_updateCount == 0) _mapController.move(LatLng(lat, lng), 15);
            _updateCount++;
          }
          _status = "Live tracking active";
        } else if (type == 'PREDICTION_UPDATE') {
          _eta = (payload['eta_minutes'] as num?)?.toDouble() ?? 0.0;
          _status = payload['status'] as String? ?? "On Route";
        }
      });
    } catch (e) {
      debugPrint("Error processing location message: $e");
    }
  }

  @override
  void dispose() {
    _notifSubscription?.cancel();
    _locationSubscription?.cancel();
    _locationChannel?.sink.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Track Bus ${widget.bus.busNumber}'),
      ),
      body: Column(
        children: [
          // Status Header
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.blue.shade50,
            child: Row(
              children: [
                const Icon(Icons.timer, color: Colors.blue),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    "ETA: ${_eta.toStringAsFixed(0)} mins - $_status",
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
          // Map Area
          Expanded(
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: _busPositions.isNotEmpty
                    ? _busPositions.values.first
                    : const LatLng(12.8446, 80.2146),
                initialZoom: 15,
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.busappvictory.app',
                ),
                MarkerLayer(
                  markers: _busPositions.entries.map((entry) {
                    return Marker(
                      point: entry.value,
                      width: 50,
                      height: 50,
                      child: const Icon(Icons.directions_bus,
                          color: Colors.blue, size: 35),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
          // Dashboard Buttons (Announcements, Docs, Requests)
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _actionButton(Icons.announcement, "Alerts",
                    () => context.push('/staff/announcements')),
                _actionButton(Icons.description, "Documents",
                    () => context.push('/staff/documents')),
                _actionButton(Icons.message, "Requests",
                    () => context.push('/staff/request')),
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _actionButton(IconData icon, String label, VoidCallback onTap) {
    return Column(
      children: [
        IconButton(icon: Icon(icon, color: Colors.blue), onPressed: onTap),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }
}
