import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:agni_college_bus_tracker/services/notification_service.dart';
import 'package:agni_college_bus_tracker/services/auth_service.dart';
import 'package:agni_college_bus_tracker/models/app_notification.dart';
import 'package:agni_college_bus_tracker/theme.dart';

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  @override
  void initState() {
    super.initState();
    // Mark all notifications as read when opening the page
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final notificationService = context.read<NotificationService>();
        final authService = context.read<AuthService>();
        final user = authService.currentUser;
        if (user != null) {
          for (final n in notificationService.forUser(user.id)) {
            if (!n.read) {
              notificationService.markRead(n.id);
            }
          }
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final notificationService = context.watch<NotificationService>();
    final authService = context.watch<AuthService>();
    final user = authService.currentUser;

    if (user == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final notifications = notificationService.forUser(user.id);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              notificationService.initialize(user.id, null);
            },
          ),
        ],
      ),
      body: notifications.isEmpty
          ? const Center(
              child: Text('No notifications yet.',
                  style: TextStyle(fontSize: 16, color: Colors.grey)),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: notifications.length,
              itemBuilder: (context, index) {
                final n = notifications[index];
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.all(16),
                    leading: CircleAvatar(
                      backgroundColor: n.read
                          ? AppColors.grey300
                          : AppColors.info.withAlpha(51),
                      child: Icon(
                        Icons.notifications,
                        color: n.read ? AppColors.grey600 : AppColors.info,
                      ),
                    ),
                    title: Text(
                      n.title,
                      style: TextStyle(
                        fontWeight:
                            n.read ? FontWeight.normal : FontWeight.bold,
                      ),
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(n.message),
                          const SizedBox(height: 4),
                          Text(
                            _formatDate(n.createdAt),
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.grey600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    trailing: n.targetScreen != null
                        ? IconButton(
                            icon: const Icon(Icons.arrow_forward_ios, 
                                color: AppColors.info),
                            onPressed: () {
                              _handleNotificationTap(context, n);
                            },
                          )
                        : null,
                    onTap: () {
                      _handleNotificationTap(context, n);
                    },
                  ),
                );
              },
            ),
    );
  }

  void _handleNotificationTap(BuildContext context, AppNotification n) async {
    // Mark as read
    final notificationService = context.read<NotificationService>();
    notificationService.markRead(n.id);

    // Navigate to target screen if available
    final targetScreen = n.targetScreen;
    if (targetScreen != null) {
      // Handle entity-specific navigation
      if (n.entityId != null) {
        // For entity-specific screens, pass the entity ID as extra
        switch (n.notificationType) {
          case 'announcement':
            context.go('/student/announcements');
            break;
          case 'document':
            context.go('/student/documents');
            break;
          case 'feedback':
            context.go('/student/feedback');
            break;
          case 'request':
            context.go('/student/my-requests');
            break;
          case 'location_started':
          case 'bus_arriving':
          case 'bus_arrived':
          case 'bus_departed':
            context.go('/track-bus-maps');
            break;
          default:
            if (targetScreen.startsWith('/')) {
              context.go(targetScreen);
            }
        }
      } else {
        // Navigate to the target screen
        if (targetScreen.startsWith('/')) {
          context.go(targetScreen);
        }
      }
    }
  }

  String _formatDate(DateTime dateTime) {
    final now = DateTime.now();
    final diff = now.difference(dateTime);

    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours} hours ago';
    if (diff.inDays < 7) return '${diff.inDays} days ago';
    return '${dateTime.day}/${dateTime.month}/${dateTime.year}';
  }
}
