import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:agni_college_bus_tracker/theme.dart';
import 'package:agni_college_bus_tracker/models/request.dart';
import 'package:agni_college_bus_tracker/services/request_service.dart';
import 'package:agni_college_bus_tracker/services/auth_service.dart';

class MyRequestsPage extends StatelessWidget {
  const MyRequestsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final requestService = context.watch<RequestService>();
    final authService = context.watch<AuthService>();
    final currentUser = authService.currentUser;
    final items = requestService.requests
        .where((r) => r.userId == currentUser?.id)
        .toList();

    Color statusColor(RequestStatus s) {
      switch (s) {
        case RequestStatus.pending:
          return AppColors.warning;
        case RequestStatus.approved:
          return AppColors.success;
        case RequestStatus.rejected:
          return AppColors.error;
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Requests'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(AppSpacing.lg),
        itemCount: items.length,
        itemBuilder: (context, index) {
          final r = items[index];
          return Container(
            margin: const EdgeInsets.only(bottom: AppSpacing.md),
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: AppColors.grey200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.mail, color: AppColors.info),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text('Bus ${r.busNumber}', // Simplified for user view
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: statusColor(r.status).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(r.status.name,
                          style: Theme.of(context)
                              .textTheme
                              .labelSmall
                              ?.copyWith(color: statusColor(r.status))),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete, color: AppColors.error),
                      onPressed: () async {
                        final requestService = context.read<RequestService>();
                        final confirmed = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text('Delete request?'),
                                content: const Text(
                                    'This will permanently cancel your request.'),
                                actions: [
                                  TextButton(
                                      onPressed: () => Navigator.pop(ctx, false),
                                      child: const Text('No')),
                                  TextButton(
                                      onPressed: () => Navigator.pop(ctx, true),
                                      child: const Text('Yes, Delete')),
                                ],
                              ),
                            ) ??
                            false;

                        if (confirmed) {
                          await requestService.deleteRequest(r.id);
                        }
                      },
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(_typeLabel(r.type),
                    style: Theme.of(context)
                        .textTheme
                        .labelMedium
                        ?.copyWith(color: AppColors.grey700)),
                const SizedBox(height: AppSpacing.xs),
                Text(r.message,
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: AppColors.grey700)),
              ],
            ),
          );
        },
      ),
    );
  }

  String _typeLabel(RequestType t) {
    switch (t) {
      case RequestType.missedBus:
        return 'Missed Bus';
      case RequestType.stopBus:
        return 'Request Stop';
      case RequestType.delayBus:
        return 'Delay Notice';
      case RequestType.busIssue:
        return 'Bus Issue';
    }
  }
}
