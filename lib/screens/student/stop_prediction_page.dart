import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import 'package:agni_college_bus_tracker/models/prediction_models.dart';
import 'package:agni_college_bus_tracker/providers/stop_prediction_provider.dart';

class StopPredictionPage extends StatefulWidget {
  const StopPredictionPage({super.key});

  @override
  State<StopPredictionPage> createState() => _StopPredictionPageState();
}

class _StopPredictionPageState extends State<StopPredictionPage> {
  final MapController _mapController = MapController();
  final TextEditingController _searchController = TextEditingController();
  late StopPredictionProvider _provider;
  bool _hasCenteredOnStop = false;

  @override
  void initState() {
    super.initState();
    _provider = context.read<StopPredictionProvider>();
    _provider.addListener(_handleProviderUpdates);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _provider.init();
    });
  }

  void _handleProviderUpdates() {
    if (!mounted) return;

    // Center on the boarding stop once it's loaded from the backend
    if (!_hasCenteredOnStop && _provider.selectedStop != null) {
      _mapController.move(_provider.selectedStop!.location, 15);
      setState(() {
        _hasCenteredOnStop = true;
      });
    }

    if (_provider.isFollowingBus && _provider.liveBusLocation != null) {
      _mapController.move(
        LatLng(
          _provider.liveBusLocation!.latitude,
          _provider.liveBusLocation!.longitude,
        ),
        _mapController.camera.zoom,
      );
    }
  }

  @override
  void dispose() {
    _provider.removeListener(_handleProviderUpdates);
    _searchController.dispose();
    _mapController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<StopPredictionProvider>();
    final PredictionResponse? prediction = provider.prediction;
    final selectedStop = provider.selectedStop;
    final previewStop = provider.previewStop;
    final activeStop = selectedStop ?? previewStop;

    return Scaffold(
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (activeStop != null)
            FloatingActionButton(
              heroTag: 'set_boarding',
              onPressed: () => provider.selectStop(activeStop),
              backgroundColor: activeStop.id == selectedStop?.id
                  ? Colors.green
                  : Colors.orange,
              child: Icon(
                activeStop.id == selectedStop?.id
                    ? Icons.how_to_reg
                    : Icons.add_location_alt,
              ),
            ),
          const SizedBox(height: 12),
          FloatingActionButton(
            heroTag: 'open_tracking',
            onPressed: () => Navigator.pushNamed(context, '/tracking'),
            backgroundColor: Colors.blue,
            child: const Icon(Icons.map_outlined),
          ),
          const SizedBox(height: 12),
          FloatingActionButton(
            heroTag: 'follow',
            onPressed: () => provider.toggleFollowBus(),
            backgroundColor: Colors.white,
            mini: true,
            child: Icon(
              provider.isFollowingBus ? Icons.gps_fixed : Icons.gps_not_fixed,
              color: provider.isFollowingBus ? Colors.blue : Colors.grey,
            ),
          ),
          SizedBox(height: activeStop != null ? 230 : 16),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter:
                  activeStop?.location ?? const LatLng(12.8446, 80.2146),
              initialZoom: 13,
              onTap: (_, __) => FocusScope.of(context).unfocus(),
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.busappvictory.app',
              ),
              MarkerLayer(
                markers: [
                  const Marker(
                    point: LatLng(12.8446, 80.2146),
                    child: Icon(Icons.school, color: Colors.red, size: 40),
                  ),
                  if (activeStop != null)
                    Marker(
                      point: activeStop.location,
                      child: const Icon(Icons.location_on,
                          color: Colors.blue, size: 40),
                    ),
                  if (selectedStop != null && activeStop?.id != selectedStop.id)
                    Marker(
                      point: selectedStop.location,
                      child: const Icon(Icons.location_on,
                          color: Colors.green, size: 30),
                    ),
                  if (provider.liveBusLocation != null)
                    Marker(
                      point: LatLng(provider.liveBusLocation!.latitude,
                          provider.liveBusLocation!.longitude),
                      child:
                          Image.asset('assets/dog.png', width: 40, height: 40),
                    ),
                ],
              ),
            ],
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  Card(
                    elevation: 4,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                    child: Focus(
                      onFocusChange: (hasFocus) {
                        if (!hasFocus) {
                          // Hide results when focus is lost
                          Future.delayed(const Duration(milliseconds: 100), () {
                            if (mounted) setState(() {});
                          });
                        }
                      },
                      child: TextField(
                        controller: _searchController,
                        onChanged: (value) {
                          provider.searchStops(value);
                          setState(() {}); // Force UI rebuild
                        },
                        decoration: InputDecoration(
                          hintText: 'Search bus stop...',
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: _searchController.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear),
                                  onPressed: () {
                                    _searchController.clear();
                                    provider.searchStops('');
                                    setState(() {});
                                  },
                                )
                              : null,
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 15,
                          ),
                        ),
                      ),
                    ),
                  ),
                  // Show search results - either filtered or all stops
                  if (provider.searchResults.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(top: 8),
                      constraints: const BoxConstraints(maxHeight: 300),
                      child: Card(
                        elevation: 4,
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: provider.searchResults.length,
                          itemBuilder: (context, index) {
                            final stop = provider.searchResults[index];
                            return Material(
                              child: ListTile(
                                leading: Icon(
                                  Icons.place,
                                  color: stop.id == selectedStop?.id
                                      ? Colors.blue
                                      : Colors.grey,
                                ),
                                title: Text(stop.name),
                                subtitle: Text(
                                  'Lat: ${stop.location.latitude.toStringAsFixed(4)}, '
                                  'Lng: ${stop.location.longitude.toStringAsFixed(4)}',
                                  style: const TextStyle(fontSize: 10),
                                ),
                                onTap: () {
                                  _searchController.clear();
                                  provider.searchStops('');
                                  provider.setPreviewStop(stop);
                                  _mapController.move(stop.location, 15);
                                  FocusScope.of(context).unfocus();
                                  setState(() {});
                                },
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (activeStop != null)
            Positioned(
              bottom: 20,
              left: 16,
              right: 16,
              child: Card(
                elevation: 8,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.blue.withValues(alpha: 0.1),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.directions_bus,
                                color: Colors.blue),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  activeStop.id == selectedStop?.id
                                      ? (prediction != null
                                          ? (prediction.isToCollege
                                              ? 'Heading to College'
                                              : 'Bus Approaching')
                                          : (provider.isLoading
                                              ? 'Updating...'
                                              : 'No Buses Active'))
                                      : 'Previewing Stop',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                                Text(
                                  activeStop.name,
                                  style: TextStyle(
                                    color: Colors.grey.shade600,
                                    fontSize: 13,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const Divider(height: 24),
                      if (activeStop.id == selectedStop?.id &&
                          prediction != null)
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          key: ValueKey(activeStop.id),
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              '${prediction.etaMinutes} min',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 20,
                                color: Colors.blue,
                              ),
                            ),
                            Text(
                              '${prediction.distanceKm.toStringAsFixed(1)} km',
                              style: TextStyle(
                                color: Colors.grey.shade600,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          TextButton.icon(
                            onPressed: () {
                              provider.refreshPredictions();
                            },
                            icon: const Icon(Icons.refresh, size: 18),
                            label: const Text('Refresh'),
                          ),
                          ElevatedButton(
                            onPressed: () {
                              _searchController.clear();
                              provider.clearSelection();
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red.shade50,
                              foregroundColor: Colors.red,
                              elevation: 0,
                            ),
                            child: const Text('Change Stop'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (activeStop == null && !provider.isLoading)
            Positioned(
              bottom: 20,
              left: 16,
              right: 16,
              child: Card(
                elevation: 4,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.search_off,
                          size: 48, color: Colors.grey),
                      const SizedBox(height: 12),
                      const Text(
                        'No Boarding Stop Set',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 18),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Search and select your boarding point using the search bar above to see bus predictions.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          Positioned(
            top: 40,
            left: 16,
            child: CircleAvatar(
              backgroundColor: Colors.white,
              child: IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.black),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
