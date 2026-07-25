import 'package:flutter/material.dart';
import 'package:agni_college_bus_tracker/models/bus.dart';
import 'package:agni_college_bus_tracker/theme.dart';

class BusCard extends StatelessWidget {
  final Bus bus;
  final Color accentColor;
  final VoidCallback? onTap;
  final VoidCallback? onTrack;
  final VoidCallback? onEdit;

  const BusCard({
    super.key,
    required this.bus,
    required this.accentColor,
    this.onTap,
    this.onTrack,
    this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: accentColor.withValues(alpha: 0.1),
                foregroundColor: accentColor,
                child: const Icon(Icons.directions_bus),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Bus ${bus.busNumber}',
                      style: Theme.of(context).textTheme.titleMedium?.bold,
                    ),
                    Text(
                      bus.route,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              if (onTrack != null)
                IconButton(
                  icon: const Icon(Icons.track_changes),
                  onPressed: onTrack,
                ),
              if (onEdit != null)
                IconButton(
                  icon: const Icon(Icons.edit),
                  onPressed: onEdit,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
