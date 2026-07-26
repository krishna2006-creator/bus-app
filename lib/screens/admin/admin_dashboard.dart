import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:agni_college_bus_tracker/theme.dart';
import 'package:agni_college_bus_tracker/services/auth_service.dart';
import 'package:agni_college_bus_tracker/services/bus_service.dart';
import 'package:agni_college_bus_tracker/services/location_service.dart';
import 'package:agni_college_bus_tracker/services/request_service.dart';
import 'package:agni_college_bus_tracker/services/trip_service.dart';
import 'package:agni_college_bus_tracker/widgets/bus_card.dart';
import 'package:agni_college_bus_tracker/widgets/pop_scope.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  final MapController _mapController = MapController();
  final TextEditingController _busSearchController = TextEditingController();
  bool _showBusList = false;
  String _busSearchQuery = '';

  @override
  void initState() {
    super.initState();
    // Refresh data when dashboard opens
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<BusService>().initialize();
      context.read<LocationService>().initialize();
      context.read<TripService>().initialize();
    });
  }

  @override
  void dispose() {
    _busSearchController.dispose();
    super.dispose();
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
                leading: const Icon(Icons.settings),
                title: const Text('Settings'),
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
      final auth = context.read<AuthService>();
      await auth.logout(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final authService = context.watch<AuthService>();
    if (authService.currentUser == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.go('/login');
      });
      return const Center(child: CircularProgressIndicator());
    }
    final busService = context.watch<BusService>();
    final locService = context.watch<LocationService>();
    final requestService = context.watch<RequestService>();
    final tripService = context.watch<TripService>();

    try {
      final markers = locService.allLocations.values.map((l) {
        final pos = LatLng(l.latitude, l.longitude);

        return Marker(
          width: 80,
          height: 80,
          point: pos,
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: const [
                    BoxShadow(color: Colors.black26, blurRadius: 4)
                  ],
                ),
                child: Text(
                  'B${l.busNumber}\n${l.speed.toStringAsFixed(1)}km/h',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Colors.black),
                ),
              ),
              Icon(
                Icons.directions_bus,
                color:
                    l.isSharedByStudent ? Colors.orange : AppColors.adminBlue,
                size: 34,
              ),
            ],
          ),
        );
      }).toList();

      LatLng initialCenter;
      if (locService.allLocations.isEmpty) {
        initialCenter = const LatLng(12.8446, 80.2146);
      } else {
        final firstLoc = locService.allLocations.values.first;
        initialCenter = LatLng(firstLoc.latitude, firstLoc.longitude);
      }

      return AppPopScope(
        canPop: false,
        child: Scaffold(
          body: SafeArea(
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        AppColors.adminBlue,
                        AppColors.adminBlue.withAlpha(204),
                      ],
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(AppRadius.md),
                            ),
                            child: Icon(Icons.admin_panel_settings,
                                color: AppColors.white, size: 28),
                          ),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Admin Dashboard',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleLarge
                                      ?.copyWith(
                                        color: AppColors.white,
                                        fontWeight: FontWeight.bold,
                                      ),
                                ),
                                Text(
                                  'Welcome, ${authService.currentUser?.name ?? "Admin"}',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodyMedium
                                      ?.copyWith(
                                        color: AppColors.white.withAlpha(230),
                                      ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: Icon(Icons.settings, color: AppColors.white),
                            onPressed: () => _showDashboardSettings(context),
                          ),
                          IconButton(
                            icon: Icon(Icons.refresh, color: AppColors.white),
                            onPressed: () async {
                              final busService = context.read<BusService>();
                              final locationService =
                                  context.read<LocationService>();
                              final tripService = context.read<TripService>();
                              await busService.initialize();
                              await locationService.initialize();
                              await tripService.initialize();
                              if (mounted) setState(() {});
                            },
                            tooltip: 'Refresh data',
                          ),
                          IconButton(
                            icon: Icon(Icons.logout, color: AppColors.white),
                            onPressed: () => _handleLogout(context),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      Row(
                        children: [
                          _StatCard(
                            icon: Icons.directions_bus,
                            count: busService.buses.length.toString(),
                            label: 'Total Buses',
                          ),
                          const SizedBox(width: AppSpacing.md),
                          _StatCard(
                            icon: Icons.pending_actions,
                            count: requestService.pendingRequests.length
                                .toString(),
                            label: 'Requests',
                          ),
                          const SizedBox(width: AppSpacing.md),
                          _StatCard(
                            icon: Icons.trip_origin,
                            count: tripService.activeTrips.length.toString(),
                            label: 'Active Trips',
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Expanded(
                  flex: 1,
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Stack(
                      children: [
                        FlutterMap(
                          mapController: _mapController,
                          options: MapOptions(
                            initialCenter: initialCenter,
                            initialZoom: 13,
                          ),
                          children: [
                            TileLayer(
                              urlTemplate:
                                  'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                              userAgentPackageName: 'com.busappvictory.app',
                            ),
                            MarkerLayer(markers: markers),
                          ],
                        ),
                        Positioned(
                          top: 10,
                          right: 10,
                          child: Column(
                            children: [
                              FloatingActionButton.small(
                                heroTag: 'refresh_btn',
                                onPressed: () async {
                                  await context
                                      .read<LocationService>()
                                      .initialize();
                                  setState(() {});
                                },
                                backgroundColor: AppColors.white,
                                child: const Icon(Icons.refresh,
                                    color: AppColors.adminBlue),
                              ),
                              const SizedBox(height: 8),
                              FloatingActionButton.small(
                                heroTag: 'info_btn',
                                onPressed: () => setState(
                                    () => _showBusList = !_showBusList),
                                backgroundColor: AppColors.white,
                                child: Icon(Icons.info_outline,
                                    color: AppColors.adminBlue),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
                  child: Row(
                    children: [
                      Expanded(
                        child: _QuickActionButton(
                          icon: Icons.add_circle,
                          label: 'Add Bus',
                          color: AppColors.adminBlue,
                          onTap: () => context.push('/admin/add-bus'),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: _QuickActionButton(
                          icon: Icons.announcement,
                          label: 'Announcements',
                          color: AppColors.info,
                          onTap: () => context.push('/admin/announcements'),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: _QuickActionButton(
                          icon: Icons.inbox,
                          label: 'Requests',
                          color: AppColors.warning,
                          onTap: () => context.push('/admin/requests'),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: _QuickActionButton(
                          icon: Icons.upload_file,
                          label: 'Documents',
                          color: AppColors.studentGreen,
                          onTap: () => context.push('/admin/documents'),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                  child: Row(
                    children: [
                      Expanded(
                        child: _QuickActionButton(
                          icon: Icons.group,
                          label: 'Manage Drivers',
                          color: AppColors.adminBlue,
                          onTap: () => context.push('/admin/drivers'),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: _QuickActionButton(
                          icon: Icons.notifications,
                          label: 'Notifications',
                          color: AppColors.info,
                          onTap: () => context.push('/notifications'),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: _QuickActionButton(
                          icon: Icons.feedback,
                          label: 'Feedbacks',
                          color: AppColors.warning,
                          onTap: () => context.push('/admin/feedback'),
                        ),
                      ),
                    ],
                  ),
                ),
                if (_showBusList)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
                    child: TextField(
                      controller: _busSearchController,
                      decoration: InputDecoration(
                        hintText: 'Search buses by number or route',
                        prefixIcon: const Icon(Icons.search),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppRadius.md),
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
                      onChanged: (value) =>
                          setState(() => _busSearchQuery = value),
                    ),
                  ),
                if (_showBusList)
                  Expanded(
                    child: ListView.builder(
                      padding:
                          const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
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
                        return BusCard(
                          bus: bus,
                          accentColor: AppColors.adminBlue,
                          onTap: () =>
                              context.push('/admin/bus-details', extra: bus),
                          onTrack: () =>
                              context.push('/admin/track-bus', extra: bus),
                          onEdit: () =>
                              context.push('/admin/edit-bus', extra: bus),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    } catch (e) {
      debugPrint('Error building admin dashboard: $e');
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              Text('Error loading dashboard: $e'),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => setState(() {}),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String count;
  final String label;

  const _StatCard(
      {required this.icon, required this.count, required this.label});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.white.withAlpha(51),
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Column(
          children: [
            Icon(icon, color: AppColors.white, size: 24),
            const SizedBox(height: AppSpacing.xs),
            Text(
              count,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: AppColors.white,
                    fontWeight: FontWeight.bold,
                  ),
            ),
            Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppColors.white.withAlpha(230),
                  ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _QuickActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        decoration: BoxDecoration(
          color: color.withAlpha(26),
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: color.withAlpha(77)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: AppSpacing.xs),
            Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w600,
                  ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
