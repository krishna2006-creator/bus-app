import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:agni_college_bus_tracker/services/auth_service.dart';
import 'package:agni_college_bus_tracker/services/bus_service.dart';
import 'package:agni_college_bus_tracker/services/location_service.dart';
import 'package:agni_college_bus_tracker/providers/stop_prediction_provider.dart';
import 'package:agni_college_bus_tracker/services/announcement_service.dart';
import 'package:agni_college_bus_tracker/services/notification_service.dart';
import 'package:agni_college_bus_tracker/models/user.dart';
import 'package:agni_college_bus_tracker/screens/admin/admin_live_tracking_screen.dart';

class StudentDashboard extends StatefulWidget {
  const StudentDashboard({super.key});

  @override
  State<StudentDashboard> createState() => _StudentDashboardState();
}

class _StudentDashboardState extends State<StudentDashboard> {
  final Set<String> _dismissedAnnouncements = {};
  final TextEditingController _busSearchController = TextEditingController();
  String _busSearchQuery = '';

  @override
  void initState() {
    super.initState();
    // Data will load through provider watchers and refresh buttons
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final user = auth.currentUser;
    if (user == null) return const Center(child: CircularProgressIndicator());

    final busService = context.watch<BusService>();
    final annService = context.watch<AnnouncementService>();
    final notificationSvc = context.watch<NotificationService>();

    final announcements = annService
        .getAnnouncementsForRole(UserRole.student)
        .where((a) => !_dismissedAnnouncements.contains(a.id))
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text("Bus Tracking Dashboard"),
        centerTitle: true,
        backgroundColor: Colors.blueAccent,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => _showDashboardSettings(context),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () async {
              // Refresh bus list, locations, announcements
              final locationService = context.read<LocationService>();
              final announcementService = context.read<AnnouncementService>();
              await busService.initialize();
              await locationService.initialize();
              await announcementService.initialize();
            },
            tooltip: 'Refresh data',
          ),
          IconButton(
            icon: Stack(
              children: [
                const Icon(Icons.notifications),
                Builder(builder: (ctx) {
                  final unreadCount = notificationSvc
                      .forUser(user.id)
                      .where((n) => !n.read)
                      .length;
                  if (unreadCount == 0) return const SizedBox.shrink();
                  return Positioned(
                    right: 0,
                    top: 0,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                          color: Colors.red,
                          borderRadius: BorderRadius.circular(6)),
                      constraints:
                          const BoxConstraints(minHeight: 12, minWidth: 12),
                      child: Text('$unreadCount',
                          style:
                              const TextStyle(color: Colors.white, fontSize: 8),
                          textAlign: TextAlign.center),
                    ),
                  );
                }),
              ],
            ),
            onPressed: () => context.push('/notifications'),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => _handleLogout(context),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Welcome Card
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              color: Colors.blue.shade50,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 30,
                      backgroundColor: Colors.blueAccent,
                      child: Text(
                          user.name != null && user.name!.isNotEmpty
                              ? user.name![0].toUpperCase()
                              : "U",
                          style: const TextStyle(
                              fontSize: 24, color: Colors.white)),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("Welcome, ${user.name ?? 'Student'}",
                              style: const TextStyle(
                                  fontSize: 20, fontWeight: FontWeight.bold)),
                          Text(
                              "Role: Student | Pinned Buses: ${user.pinnedBuses.length}",
                              style: const TextStyle(
                                  fontSize: 14, color: Colors.grey)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),
            const Text("Quick Actions",
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),

            Row(
              children: [
                Expanded(
                    child: _buildFeatureCard(context,
                        title: "New Request",
                        description: "Leave or route change",
                        icon: Icons.add_circle,
                        color: Colors.green,
                        onTap: () => context.push('/student/request'))),
                const SizedBox(width: 12),
                Expanded(
                    child: _buildFeatureCard(context,
                        title: "My Requests",
                        description: "View status",
                        icon: Icons.history,
                        color: Colors.blueGrey,
                        onTap: () => context.push('/student/my-requests'))),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                    child: _buildFeatureCard(context,
                        title: "Announcements",
                        description: "${announcements.length} updates",
                        icon: Icons.campaign,
                        color: Colors.orange,
                        onTap: () => context.push('/student/announcements'))),
                const SizedBox(width: 12),
                Expanded(
                    child: _buildFeatureCard(context,
                        title: "Documents",
                        description: "View from Admin",
                        icon: Icons.description,
                        color: Colors.blue,
                        onTap: () => context.push('/student/documents'))),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                    child: _buildFeatureCard(context,
                        title: "Feedback / Complaint",
                        description: "Send feedback to admin",
                        icon: Icons.feedback,
                        color: Colors.purple,
                        onTap: () => context.push('/student/feedback'))),
                const SizedBox(width: 12),
                Expanded(
                    child: _buildFeatureCard(context,
                        title: "Live Bus Tracking",
                        description: "Track buses on map",
                        icon: Icons.map,
                        color: Colors.deepOrange,
                        onTap: () => context.push('/student/live-tracking'))),
              ],
            ),
            const SizedBox(height: 16),

            // Live Tracking Section - Only show if tracking is actually live
            _buildConditionalLiveTracking(context),

            // Stop Prediction Widget - ONLY SHOW IF BUSES ARE PINNED AND HAS SELECTED STOP
            if (user.pinnedBuses.isNotEmpty) ...[
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text("Bus ETA to My Stop",
                    style:
                        TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              ),
              _buildStopPredictionWidget(context, user),
              const SizedBox(height: 16),
            ],

            const Text("Pinned & All Buses",
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            TextField(
              controller: _busSearchController,
              decoration: InputDecoration(
                hintText: 'Search buses by number or route',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                suffixIcon: _busSearchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _busSearchController.clear();
                          setState(() => _busSearchQuery = '');
                        },
                      )
                    : null,
              ),
              onChanged: (value) => setState(() => _busSearchQuery = value),
            ),
            const SizedBox(height: 12),

            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: busService.buses.where((bus) {
                final query = _busSearchQuery.toLowerCase();
                return query.isEmpty ||
                    bus.busNumber.toLowerCase().contains(query) ||
                    bus.route.toLowerCase().contains(query);
              }).length,
              itemBuilder: (context, index) {
                final filteredBuses = busService.buses.where((bus) {
                  final query = _busSearchQuery.toLowerCase();
                  return query.isEmpty ||
                      bus.busNumber.toLowerCase().contains(query) ||
                      bus.route.toLowerCase().contains(query);
                }).toList();
                final bus = filteredBuses[index];
                final isPinned = auth.isBusPinned(bus.busNumber);
                return Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: ListTile(
                    leading: const CircleAvatar(
                        backgroundColor: Colors.blueAccent,
                        child: Icon(Icons.directions_bus,
                            color: Colors.white, size: 20)),
                    title: Text("Bus ${bus.busNumber}",
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text(bus.route,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                            icon: const Icon(Icons.track_changes,
                                color: Colors.redAccent),
                            onPressed: () =>
                                context.push('/track-bus-maps', extra: bus)),
                        IconButton(
                            icon: const Icon(Icons.location_on,
                                color: Colors.green),
                            onPressed: () => context
                                .push('/student/share-location', extra: bus)),
                        IconButton(
                          icon: Icon(
                              isPinned
                                  ? Icons.push_pin
                                  : Icons.push_pin_outlined,
                              color: isPinned ? Colors.blue : Colors.grey),
                          onPressed: () async {
                            if (isPinned) {
                              await auth.unpinBus(bus.busNumber);
                            } else {
                              await auth.pinBus(bus.busNumber);
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showDashboardSettings(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.person),
                title: const Text('Profile'),
                onTap: () => Navigator.pop(ctx),
              ),
              ListTile(
                leading: const Icon(Icons.help_outline),
                title: const Text('Support'),
                onTap: () => Navigator.pop(ctx),
              ),
              ListTile(
                leading: const Icon(Icons.logout),
                title: const Text('Logout'),
                onTap: () {
                  Navigator.pop(ctx);
                  _handleLogout(context);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _handleLogout(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to log out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Logout', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      final auth = Provider.of<AuthService>(context, listen: false);
      await auth.logout(context);
    }
  }

  Widget _buildConditionalLiveTracking(BuildContext context) {
    final auth = context.watch<AuthService>();
    final user = auth.currentUser;

    // Only show the live tracking map if the student has pinned buses.
    // This keeps the tracking context visible for the buses they care about.
    final hasPinnedBuses = user?.pinnedBuses.isNotEmpty ?? false;

    if (!hasPinnedBuses) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("Live Tracking",
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        const AdminLiveTrackingScreen(),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildStopPredictionWidget(BuildContext context, User user) {
    final provider = context.watch<StopPredictionProvider>();
    final prediction = provider.prediction;
    final selectedStop = provider.selectedStop;

    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      elevation: 6,
      child: Column(
        children: [
          SizedBox(
            height: 140,
            child: FlutterMap(
              options: MapOptions(
                initialCenter: selectedStop?.location ??
                    const LatLng(12.836371, 80.222332), // College
                initialZoom: 13,
                interactionOptions:
                    const InteractionOptions(flags: InteractiveFlag.none),
              ),
              children: [
                TileLayer(
                    urlTemplate:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.busappvictory.app'),
                MarkerLayer(markers: [
                  const Marker(
                      point: LatLng(12.836371, 80.222332),
                      child: Icon(Icons.school, color: Colors.red, size: 35)),
                  if (selectedStop != null)
                    Marker(
                        point: selectedStop.location,
                        child: const Icon(Icons.location_on,
                            color: Colors.blue, size: 35)),
                  if (provider.liveBusLocation != null)
                    Marker(
                      point: LatLng(provider.liveBusLocation!.latitude,
                          provider.liveBusLocation!.longitude),
                      child:
                          Image.asset('assets/dog.png', width: 30, height: 30),
                    ),
                ]),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.white,
            child: Row(
              children: [
                const Icon(Icons.location_searching, color: Colors.blueAccent),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                          prediction != null
                              ? "${prediction.etaMinutes} min away"
                              : (selectedStop != null
                                  ? "Tracking ${selectedStop.name}"
                                  : "No Stop Set"),
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 17)),
                      Text(
                          prediction != null
                              ? "${prediction.distanceKm.toStringAsFixed(1)} km to your stop"
                              : "Tap to set boarding point",
                          style: const TextStyle(
                              color: Colors.grey, fontSize: 13)),
                    ],
                  ),
                ),
                ElevatedButton(
                  onPressed: () => context.push('/student/stop-prediction'),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blueAccent),
                  child: Text(prediction != null ? "Details" : "Set Stop",
                      style: TextStyle(color: Colors.white)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureCard(BuildContext context,
      {required String title,
      required String description,
      required IconData icon,
      required Color color,
      required VoidCallback onTap}) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.1),
                      shape: BoxShape.circle),
                  child: Icon(icon, color: color, size: 24)),
              const SizedBox(height: 8),
              Text(title,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.bold)),
              const SizedBox(height: 2),
              Text(description,
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ),
    );
  }
}
