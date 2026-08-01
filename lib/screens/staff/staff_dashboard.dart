import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:agni_college_bus_tracker/services/auth_service.dart';
import 'package:agni_college_bus_tracker/services/bus_service.dart';
import 'package:agni_college_bus_tracker/services/location_service.dart';
import 'package:agni_college_bus_tracker/services/announcement_service.dart';
import 'package:agni_college_bus_tracker/services/notification_service.dart';
import 'package:agni_college_bus_tracker/models/user.dart';
import 'package:agni_college_bus_tracker/screens/admin/admin_live_tracking_screen.dart';
import 'package:agni_college_bus_tracker/widgets/pop_scope.dart';

class StaffDashboard extends StatefulWidget {
  const StaffDashboard({super.key});

  @override
  State<StaffDashboard> createState() => _StaffDashboardState();
}

class _StaffDashboardState extends State<StaffDashboard> {
  final Set<String> _dismissedAnnouncements = {};
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Refresh announcements when dashboard opens
      final announcementService = context.read<AnnouncementService>();
      announcementService.initialize();
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final user = auth.currentUser;
    if (user == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.go('/login');
      });
      return const Center(child: CircularProgressIndicator());
    }

    final busService = context.watch<BusService>();
    final announcementService = context.watch<AnnouncementService>();
    final notificationService = context.watch<NotificationService>();

    final announcements = announcementService
        .getAnnouncementsForRole(UserRole.staff)
        .where((a) => !_dismissedAnnouncements.contains(a.id))
        .take(3)
        .toList();

    return AppPopScope(
      canPop: false,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Staff Dashboard'),
          automaticallyImplyLeading: false,
          actions: [
            IconButton(
              icon: const Icon(Icons.settings),
              onPressed: () => _showDashboardSettings(context),
            ),
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () async {
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
                  Builder(builder: (context) {
                    final unread = notificationService
                        .forUser(user.id)
                        .where((n) => !n.read)
                        .length;
                    if (unread == 0) {
                      return const SizedBox.shrink();
                    }
                    return Positioned(
                      right: 0,
                      top: 0,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                            color: Colors.red,
                            borderRadius: BorderRadius.circular(6)),
                        constraints:
                            const BoxConstraints(minWidth: 12, minHeight: 12),
                        child: Text('$unread',
                            style: const TextStyle(
                                color: Colors.white, fontSize: 8),
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
              onPressed: () => auth.logout(context),
            ),
          ],
        ),
        body: Column(
          children: [
            const AdminLiveTrackingScreen(),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _QuickActionButton(
                          icon: Icons.announcement,
                          label: 'Announcements',
                          color: Colors.orange,
                          onTap: () => context.push('/staff/announcements'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _QuickActionButton(
                          icon: Icons.description,
                          label: 'Documents',
                          color: Colors.blue,
                          onTap: () => context.push('/staff/documents'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                   Row(
                     children: [
                       Expanded(
                         child: _QuickActionButton(
                           icon: Icons.request_page,
                           label: 'Requests',
                           color: Colors.green,
                           onTap: () => context.push('/staff/requests'),
                         ),
                       ),
                       const SizedBox(width: 12),
                       Expanded(
                         child: _QuickActionButton(
                           icon: Icons.map,
                           label: 'Live Tracking',
                           color: Colors.deepOrange,
                           onTap: () => context.push('/staff/live-tracking'),
                         ),
                       ),
                     ],
                   ),
                  const SizedBox(height: 12),
                  const Text('Pinned Buses',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Search buses by number or route',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _searchQuery = '');
                              },
                            )
                          : null,
                    ),
                    onChanged: (value) => setState(() => _searchQuery = value),
                  ),
                  const SizedBox(height: 12),
                  for (var busNum in user.pinnedBuses.where((busNum) {
                    final bus = busService.getBusByNumber(busNum);
                    if (bus == null) return false;
                    final query = _searchQuery.toLowerCase();
                    return query.isEmpty ||
                        bus.busNumber.toLowerCase().contains(query) ||
                        bus.route.toLowerCase().contains(query);
                  }))
                    Builder(builder: (ctx) {
                      final bus = busService.getBusByNumber(busNum);
                      if (bus == null || bus.busNumber.isEmpty) {
                        return const SizedBox.shrink();
                      }
                      return Card(
                        child: ListTile(
                          leading: const Icon(Icons.directions_bus),
                          title: Text('Bus ${bus.busNumber}'),
                          subtitle: Text(bus.route),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.track_changes,
                                    color: Colors.redAccent),
                                onPressed: () => context
                                    .push('/staff/track-bus', extra: bus),
                              ),
                              IconButton(
                                icon: const Icon(Icons.push_pin,
                                    color: Colors.blue),
                                onPressed: () => auth.unpinBus(bus.busNumber),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                  const SizedBox(height: 8),
                  const Text('All Buses',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  for (var bus in busService.buses.where((bus) {
                    final query = _searchQuery.toLowerCase();
                    return query.isEmpty ||
                        bus.busNumber.toLowerCase().contains(query) ||
                        bus.route.toLowerCase().contains(query);
                  }))
                    Card(
                      child: ListTile(
                        title: Text('Bus ${bus.busNumber}'),
                        subtitle: Text(bus.route),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.track_changes,
                                  color: Colors.redAccent),
                              onPressed: () =>
                                  context.push('/staff/track-bus', extra: bus),
                            ),
                            IconButton(
                              icon: Icon(
                                  auth.isBusPinned(bus.busNumber)
                                      ? Icons.push_pin
                                      : Icons.push_pin_outlined,
                                  color: auth.isBusPinned(bus.busNumber)
                                      ? Colors.blue
                                      : Colors.grey),
                              onPressed: () {
                                if (auth.isBusPinned(bus.busNumber)) {
                                  auth.unpinBus(bus.busNumber);
                                } else {
                                  auth.pinBus(bus.busNumber);
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(height: 8),
                  const Text('Latest Announcements',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  for (var a in announcements)
                    Card(
                      child: ListTile(
                        title: Text(a.title),
                        subtitle: Text(a.message,
                            maxLines: 2, overflow: TextOverflow.ellipsis),
                        trailing: IconButton(
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: () =>
                              setState(() => _dismissedAnnouncements.add(a.id)),
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
                leading: const Icon(Icons.support_agent),
                title: const Text('Support'),
                onTap: () => Navigator.pop(ctx),
              ),
              ListTile(
                leading: const Icon(Icons.logout),
                title: const Text('Logout'),
                onTap: () {
                  Navigator.pop(ctx);
                  context.read<AuthService>().logout(context);
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

class _QuickActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;

  const _QuickActionButton({
    required this.icon,
    required this.label,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          children: [
            Icon(icon, size: 24, color: color),
            const SizedBox(height: 8),
            Text(label,
                style: TextStyle(
                    color: color, fontSize: 12, fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }
}
