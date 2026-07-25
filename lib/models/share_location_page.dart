import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/bus.dart';
import '../../services/api_service.dart';

class ShareLocationPage extends StatefulWidget {
  final Bus bus;

  const ShareLocationPage({super.key, required this.bus});

  @override
  State<ShareLocationPage> createState() => _ShareLocationPageState();
}

class _ShareLocationPageState extends State<ShareLocationPage> {
  bool _isLoading = false;
  String? _locationLink;
  String? _lastUpdated;

  @override
  void initState() {
    super.initState();
    _fetchBusLocation();
  }

  Future<void> _fetchBusLocation() async {
    setState(() => _isLoading = true);
    try {
      final locationData = await ApiService.getBusLocation(widget.bus.id);
      if (locationData != null) {
        final lat = locationData['latitude'];
        final lng = locationData['longitude'];
        // Create a Google Maps link
        final link =
            "https://www.google.com/maps/search/?api=1&query=$lat,$lng";

        setState(() {
          _locationLink = link;
          _lastUpdated = DateTime.now().toString().substring(11, 16); // HH:MM
        });
      }
    } catch (e) {
      // Handle error
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to fetch location: $e')),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _copyToClipboard() {
    if (_locationLink != null) {
      Clipboard.setData(ClipboardData(text: _locationLink!));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Location link copied to clipboard!')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Share Bus Location'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh Location',
            onPressed: _isLoading ? null : _fetchBusLocation,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.share_location, size: 80, color: Colors.blue),
            const SizedBox(height: 24),
            Text(
              "Share Bus ${widget.bus.busNumber}",
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              "Send this link to your parents or guardians so they can track the bus location.",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey, fontSize: 16),
            ),
            const SizedBox(height: 32),
            if (_isLoading)
              const Center(child: CircularProgressIndicator())
            else if (_locationLink != null) ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey[300]!),
                ),
                child: Column(
                  children: [
                    Text(
                      _locationLink!,
                      style: const TextStyle(
                          color: Colors.blue,
                          decoration: TextDecoration.underline),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text("Last updated: $_lastUpdated",
                        style:
                            const TextStyle(fontSize: 12, color: Colors.grey)),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _copyToClipboard,
                icon: const Icon(Icons.copy),
                label: const Text("Copy Link"),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ] else
              const Center(child: Text("Location not available yet.")),
          ],
        ),
      ),
    );
  }
}
