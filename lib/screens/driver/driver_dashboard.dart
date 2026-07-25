import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:agni_college_bus_tracker/theme.dart';
import 'package:agni_college_bus_tracker/widgets/pop_scope.dart';
import 'package:agni_college_bus_tracker/services/auth_service.dart';
import 'package:agni_college_bus_tracker/services/bus_service.dart';
import 'package:agni_college_bus_tracker/services/trip_service.dart';
import 'package:agni_college_bus_tracker/models/trip.dart';

class DriverDashboard extends StatefulWidget {
  const DriverDashboard({super.key});

  @override
  State<DriverDashboard> createState() => _DriverDashboardState();
}

class _DriverDashboardState extends State<DriverDashboard> {
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
    final tripService = context.watch<TripService>();
    final user = authService.currentUser!;

    final assignedBus = user.assignedBusNumber != null
        ? busService.getBusByNumber(user.assignedBusNumber!)
        : null;

    final activeTrip = assignedBus != null
        ? tripService.getActiveTripForBus(assignedBus.busNumber)
        : null;

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
                      AppColors.driverRed,
                      AppColors.driverRed.withAlpha(204)
                    ],
                  ),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppColors.white.withAlpha(51),
                            borderRadius: BorderRadius.circular(AppRadius.md),
                          ),
                          child: const Icon(Icons.local_shipping,
                              color: AppColors.white, size: 28),
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Driver Dashboard',
                                style: context.textStyles.titleLarge?.copyWith(
                                  color: AppColors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                'Welcome, ${user.name ?? "Driver"}',
                                style: context.textStyles.bodyMedium?.copyWith(
                                  color: AppColors.white.withAlpha(230),
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.settings,
                              color: AppColors.white),
                          onPressed: () => _showDashboardSettings(context),
                        ),
                        IconButton(
                          icon:
                              const Icon(Icons.logout, color: AppColors.white),
                          onPressed: () async {
                            await context.read<AuthService>().logout(context);
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  children: [
                    if (assignedBus == null) ...[
                      _buildNoBusWarning(context)
                    ] else ...[
                      _buildBusInfoCard(context, assignedBus, activeTrip),
                      const SizedBox(height: AppSpacing.lg),
                      _LargeActionButton(
                        icon: Icons.location_on,
                        label: 'Share Live Location',
                        color: AppColors.info,
                        onTap: () => context.push('/driver/share-location'),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      if (activeTrip == null)
                        _LargeActionButton(
                          icon: Icons.play_circle_filled,
                          label: 'Start Official Trip',
                          color: AppColors.success,
                          onTap: () => _handleStartTrip(
                              context, assignedBus.busNumber, user.name),
                        )
                      else
                        _LargeActionButton(
                          icon: Icons.stop_circle,
                          label: 'End Current Trip',
                          color: AppColors.error,
                          onTap: () => _handleEndTrip(context, activeTrip.id),
                        ),
                      const SizedBox(height: AppSpacing.xl),
                      Text(
                        'Management',
                        style: context.textStyles.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: AppColors.grey900,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      GridView.count(
                        shrinkWrap: true,
                        crossAxisCount: 2,
                        crossAxisSpacing: AppSpacing.md,
                        mainAxisSpacing: AppSpacing.md,
                        physics: const NeverScrollableScrollPhysics(),
                        children: [
                          _ActionCard(
                            icon: Icons.announcement,
                            label: 'Announcements',
                            color: AppColors.staffOrange,
                            onTap: () => context.push('/driver/announcements'),
                          ),
                          _ActionCard(
                            icon: Icons.description,
                            label: 'Documents',
                            color: AppColors.studentGreen,
                            onTap: () => context.push('/driver/documents'),
                          ),
                          _ActionCard(
                            icon: Icons.notifications,
                            label: 'My Alerts',
                            color: AppColors.info,
                            onTap: () => context.push('/notifications'),
                          ),
                          _ActionCard(
                            icon: Icons.help_outline,
                            label: 'Support',
                            color: AppColors.warning,
                            onTap: () => context.push('/driver/my-requests'),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
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
                  context.read<AuthService>().logout(context);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildNoBusWarning(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.warning.withAlpha(26),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.warning.withAlpha(77)),
      ),
      child: Column(
        children: [
          const Icon(Icons.warning, color: AppColors.warning, size: 48),
          const SizedBox(height: AppSpacing.md),
          Text('No Bus Assigned', style: context.textStyles.titleLarge?.bold),
          const SizedBox(height: AppSpacing.sm),
          const Text('Please contact admin to get a bus assigned.',
              textAlign: TextAlign.center),
        ],
      ),
    );
  }

  Widget _buildBusInfoCard(
      BuildContext context, dynamic bus, dynamic activeTrip) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        boxShadow: [
          BoxShadow(color: AppColors.grey300.withAlpha(77), blurRadius: 8)
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Bus ${bus.busNumber}',
              style: context.textStyles.headlineSmall?.copyWith(
                  color: AppColors.driverRed, fontWeight: FontWeight.bold)),
          Text(bus.route,
              style: context.textStyles.titleMedium
                  ?.copyWith(color: AppColors.grey700)),
          const Divider(height: 32),
          Row(
            children: [
              Icon(
                  activeTrip != null
                      ? Icons.check_circle
                      : Icons.pause_circle_filled,
                  color: activeTrip != null
                      ? AppColors.success
                      : AppColors.grey400),
              const SizedBox(width: AppSpacing.sm),
              Text(activeTrip != null ? 'Trip Active' : 'Waiting to Start',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: activeTrip != null
                          ? AppColors.success
                          : AppColors.grey600)),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _handleStartTrip(
      BuildContext context, String busNum, String? name) async {
    final messenger = ScaffoldMessenger.of(context);
    final tripService = context.read<TripService>();
    final trip = Trip(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      busNumber: busNum,
      driverName: name ?? 'Unknown',
      startTime: DateTime.now(),
    );
    await tripService.startTrip(trip);
    if (!mounted) return;
    messenger.showSnackBar(
        const SnackBar(content: Text('Trip started successfully!')));
  }

  Future<void> _handleEndTrip(BuildContext context, String tripId) async {
    final messenger = ScaffoldMessenger.of(context);
    final tripService = context.read<TripService>();
    await tripService.endTrip(tripId);
    if (!mounted) return;
    messenger.showSnackBar(
        const SnackBar(content: Text('Trip ended successfully!')));
  }
}

class _LargeActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _LargeActionButton(
      {required this.icon,
      required this.label,
      required this.color,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 28),
      label: Text(label,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        minimumSize: const Size(double.infinity, 60),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ActionCard(
      {required this.icon,
      required this.label,
      required this.color,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Container(
        decoration: BoxDecoration(
          color: color.withAlpha(26),
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 32),
            const SizedBox(height: 8),
            Text(label,
                style: TextStyle(color: color, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}
