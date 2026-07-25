import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:agni_college_bus_tracker/models/bus_location.dart';
import 'package:agni_college_bus_tracker/models/user.dart';
import 'package:agni_college_bus_tracker/services/location_service.dart';
import 'package:agni_college_bus_tracker/services/auth_service.dart';
import 'package:agni_college_bus_tracker/services/api_service.dart';

class DriverShareLocationPage extends StatefulWidget {
  const DriverShareLocationPage({super.key});

  @override
  State<DriverShareLocationPage> createState() => _DriverShareLocationPageState();
}

class _DriverShareLocationPageState extends State<DriverShareLocationPage> {
  final MapController _mapController = MapController();
  StreamSubscription<Position>? _positionSub;
  LatLng? _currentPos;
  bool _isManualRefreshing = false;

  @override
  void initState() {
    super.initState();
    _startSharing();
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    super.dispose();
  }

  Future<void> _startSharing() async {
    final authService = context.read<AuthService>();
    final messenger = ScaffoldMessenger.of(context);
    final user = authService.currentUser;
    final busNumber = user?.assignedBusNumber;

    if (user == null || busNumber == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('No bus assigned. Cannot share location.')),
      );
      context.pop();
      return;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (mounted) {
          messenger.showSnackBar(
            const SnackBar(content: Text('Location permissions are required.')),
          );
          context.pop();
        }
        return;
      }
    }

    _positionSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
      ),
    ).listen((pos) {
      _updateLocationLocallyAndOnServer(pos);
    });
  }

  Future<void> _manualRefresh() async {
    if (_isManualRefreshing) return;
    setState(() => _isManualRefreshing = true);
    try {
      Position pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
      await _updateLocationLocallyAndOnServer(pos);
      _mapController.move(LatLng(pos.latitude, pos.longitude), 16);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Location Refreshed!"), duration: Duration(seconds: 1)),
        );
      }
    } catch (e) {
      debugPrint("Error refreshing location: $e");
    } finally {
      if (mounted) setState(() => _isManualRefreshing = false);
    }
  }

  Future<void> _updateLocationLocallyAndOnServer(Position pos) async {
    final authService = context.read<AuthService>();
    final locService = context.read<LocationService>();
    final user = authService.currentUser;
    final busNumber = user?.assignedBusNumber;

    if (busNumber == null) return;

    final loc = BusLocation(
      busNumber: busNumber,
      latitude: pos.latitude,
      longitude: pos.longitude,
      speed: pos.speed,
      timestamp: DateTime.now(),
      userType: UserRole.driver,
    );

    // Update locally
    locService.updateLocation(loc);
    
    // Push to server
    try {
      await ApiService.postPublicLocation(
        int.tryParse(busNumber) ?? 0,
        pos.latitude,
        pos.longitude,
        true,
      );
    } catch (e) {
      debugPrint("Failed to push location to server: $e");
    }

    if (mounted) {
      setState(() => _currentPos = LatLng(pos.latitude, pos.longitude));
    }
  }

  @override
  Widget build(BuildContext context) {
    final busNumber = context.watch<AuthService>().currentUser?.assignedBusNumber ?? '';
    return Scaffold(
      appBar: AppBar(
        title: Text('Sharing for Bus $busNumber'),
        actions: [
          _isManualRefreshing 
            ? const Padding(
                padding: EdgeInsets.all(16.0),
                child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)),
              )
            : IconButton(icon: const Icon(Icons.refresh), onPressed: _manualRefresh),
        ],
      ),
      body: FlutterMap(
        mapController: _mapController,
        options: MapOptions(
          initialCenter: _currentPos ?? const LatLng(13.0827, 80.2707),
          initialZoom: 15,
        ),
        children: [
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.busappvictory.app',
          ),
          MarkerLayer(
            markers: [
              if (_currentPos != null)
                Marker(
                  point: _currentPos!,
                  width: 45,
                  height: 45,
                  child: Image.asset('assets/dog.png'),
                ),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.pop(),
        label: const Text('Stop Sharing'),
        icon: const Icon(Icons.stop),
        backgroundColor: Colors.red,
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }
}
