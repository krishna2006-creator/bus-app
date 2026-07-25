import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:agni_college_bus_tracker/theme.dart';
import 'package:agni_college_bus_tracker/models/user.dart';
import 'package:agni_college_bus_tracker/models/announcement.dart';
import 'package:agni_college_bus_tracker/services/announcement_service.dart';
import 'package:agni_college_bus_tracker/services/auth_service.dart';

class AnnouncementsPage extends StatefulWidget {
  final String title;
  final bool allowCreate;
  const AnnouncementsPage(
      {super.key, required this.title, this.allowCreate = false});

  @override
  State<AnnouncementsPage> createState() => _AnnouncementsPageState();
}

class _AnnouncementsPageState extends State<AnnouncementsPage> {
  void _openCreateDialog() async {
    final controllerTitle = TextEditingController();
    final controllerMessage = TextEditingController();
    final controllerBus = TextEditingController();
    AnnouncementTarget target = AnnouncementTarget.all;

    // Services and Navigators should be obtained before async gaps.
    final service = context.read<AnnouncementService>();
    final auth = context.read<AuthService>();
    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      ),
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom + AppSpacing.lg,
            top: AppSpacing.lg,
            left: AppSpacing.lg,
            right: AppSpacing.lg,
          ),
          child: StatefulBuilder(builder: (context, setStateSB) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.announcement, color: AppColors.info),
                    const SizedBox(width: AppSpacing.sm),
                    Text('New Announcement',
                        style: Theme.of(context).textTheme.titleLarge?.bold),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                TextField(
                  controller: controllerTitle,
                  decoration: InputDecoration(
                    labelText: 'Title',
                    prefixIcon: const Icon(Icons.title, color: AppColors.info),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      borderSide: const BorderSide(color: AppColors.grey300),
                    ),
                    focusedBorder: const OutlineInputBorder(
                      borderSide: BorderSide(color: AppColors.info, width: 2),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                TextField(
                  controller: controllerMessage,
                  maxLines: 5,
                  decoration: InputDecoration(
                    labelText: 'Message',
                    prefixIcon:
                        const Icon(Icons.message, color: AppColors.info),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      borderSide: const BorderSide(color: AppColors.grey300),
                    ),
                    focusedBorder: const OutlineInputBorder(
                      borderSide: BorderSide(color: AppColors.info, width: 2),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                TextField(
                  controller: controllerBus,
                  decoration: InputDecoration(
                    labelText: 'Bus Number (optional)',
                    prefixIcon:
                        const Icon(Icons.directions_bus, color: AppColors.info),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      borderSide: const BorderSide(color: AppColors.grey300),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Wrap(
                  spacing: 8,
                  children: AnnouncementTarget.values.map((t) {
                    final selected = t == target;
                    return ChoiceChip(
                      label: Text(t.name),
                      selected: selected,
                      onSelected: (_) => setStateSB(() => target = t),
                      selectedColor: AppColors.info.withValues(alpha: 0.15),
                      labelStyle: TextStyle(
                          color: selected ? AppColors.info : AppColors.grey700),
                    );
                  }).toList(),
                ),
                const SizedBox(height: AppSpacing.lg),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      if (controllerTitle.text.trim().isEmpty ||
                          controllerMessage.text.trim().isEmpty) {
                        messenger.showSnackBar(const SnackBar(
                            content: Text('Enter title and message')));
                        return;
                      }
                      final ann = Announcement(
                        id: DateTime.now().millisecondsSinceEpoch.toString(),
                        title: controllerTitle.text.trim(),
                        message: controllerMessage.text.trim(),
                        target: target,
                        busNumber: controllerBus.text.trim().isEmpty
                            ? null
                            : controllerBus.text.trim(),
                      );
                      await service.addAnnouncement(ann, auth.users);
                      nav.pop();
                    },
                    icon: const Icon(Icons.send, color: AppColors.white),
                    label: const Text('Post Announcement',
                        style: TextStyle(color: AppColors.white)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.info,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadius.md)),
                      padding:
                          const EdgeInsets.symmetric(vertical: AppSpacing.md),
                    ),
                  ),
                ),
              ],
            );
          }),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final announcementService = context.watch<AnnouncementService>();
    final authService = context.watch<AuthService>();
    final userRole = authService.currentUser?.role ?? UserRole.student;

    final items = announcementService.getAnnouncementsForRole(userRole);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        title: Text(widget.title),
        actions: [
          if (widget.allowCreate)
            IconButton(
              icon: const Icon(Icons.add, color: AppColors.info),
              onPressed: _openCreateDialog,
            ),
        ],
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(AppSpacing.lg),
        itemCount: items.length,
        itemBuilder: (context, index) {
          final a = items[index];
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
                    Icon(Icons.campaign, color: AppColors.info),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(a.title,
                          style: Theme.of(context).textTheme.titleMedium?.bold),
                    ),
                    if (a.busNumber != null)
                      Container(
                        margin: const EdgeInsets.only(right: AppSpacing.sm),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.warning.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text('Bus ${a.busNumber}',
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.withColor(AppColors.warning)),
                      ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.info.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(a.target.name,
                          style: Theme.of(context)
                              .textTheme
                              .labelSmall
                              ?.withColor(AppColors.info)),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    IconButton(
                      icon: const Icon(Icons.delete, color: AppColors.error),
                      onPressed: () async {
                        final confirmed = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text('Delete announcement?'),
                                content: const Text(
                                    'This will remove the announcement permanently.'),
                                actions: [
                                  TextButton(
                                      onPressed: () =>
                                          Navigator.pop(ctx, false),
                                      child: const Text('Cancel')),
                                  TextButton(
                                      onPressed: () =>
                                          Navigator.pop(ctx, true),
                                      child: const Text('Delete')),
                                ],
                              ),
                            ) ??
                            false;

                        if (confirmed) {
                          await announcementService.deleteAnnouncement(a.id);
                        }
                      },
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(a.message,
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.withColor(AppColors.grey700)),
              ],
            ),
          );
        },
      ),
    );
  }
}
