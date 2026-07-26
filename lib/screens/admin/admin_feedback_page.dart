import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:agni_college_bus_tracker/theme.dart';
import 'package:agni_college_bus_tracker/services/feedback_service.dart';

class AdminFeedbackPage extends StatefulWidget {
  const AdminFeedbackPage({super.key});

  @override
  State<AdminFeedbackPage> createState() => _AdminFeedbackPageState();
}

class _AdminFeedbackPageState extends State<AdminFeedbackPage> {
  @override
  void initState() {
    super.initState();
    // Refresh feedback list when page loads
    Future.microtask(() async {
      if (mounted) {
        final feedbackService = context.read<FeedbackService>();
        await feedbackService.initialize();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final feedbackService = context.watch<FeedbackService>();
    final feedbacks = feedbackService.feedbacks;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Feedbacks & Complaints'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: feedbacks.isEmpty
          ? const Center(
              child: Text('No feedbacks yet.',
                  style: TextStyle(fontSize: 16, color: Colors.grey)),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: feedbacks.length,
              itemBuilder: (context, index) {
                final feedback = feedbacks[index];
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            CircleAvatar(
                              backgroundColor: feedback.replied
                                  ? AppColors.success
                                  : AppColors.warning,
                              child: Icon(
                                feedback.replied ? Icons.check : Icons.pending,
                                color: AppColors.white,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    feedback.subject,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Text(
                                    'From: ${feedback.userName} (${feedback.userRole})',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: AppColors.grey600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          feedback.message,
                          style: const TextStyle(fontSize: 14),
                        ),
                        const SizedBox(height: 12),
                        if (feedback.replied && feedback.reply != null) ...[
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppColors.info.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Admin Reply:',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.info,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  feedback.reply!,
                                  style: const TextStyle(fontSize: 14),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                        ],
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Text(
                              _formatDate(feedback.createdAt),
                              style: TextStyle(
                                fontSize: 11,
                                color: AppColors.grey600,
                              ),
                            ),
                            const SizedBox(width: 8),
                            if (!feedback.replied)
                              TextButton.icon(
                                onPressed: () =>
                                    _showReplyDialog(context, feedback),
                                icon: const Icon(Icons.reply, size: 18),
                                label: const Text('Reply'),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }

  void _showReplyDialog(BuildContext context, dynamic feedback) {
    final replyController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Reply to: ${feedback.subject}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'From: ${feedback.userName}',
              style: TextStyle(fontSize: 12, color: AppColors.grey600),
            ),
            const SizedBox(height: 8),
            Text(
              feedback.message,
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: replyController,
              maxLines: 4,
              decoration: InputDecoration(
                labelText: 'Your Reply',
                hintText: 'Type your reply here...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final reply = replyController.text.trim();
              if (reply.isEmpty) return;

              final feedbackService =
                  Provider.of<FeedbackService>(ctx, listen: false);
              final nav = Navigator.of(ctx);
              final messenger = ScaffoldMessenger.of(ctx);
              await feedbackService.addReply(feedback.id, reply);

              nav.pop();
              messenger.showSnackBar(
                const SnackBar(content: Text('Reply sent successfully!')),
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.info),
            child: const Text('Send Reply',
                style: TextStyle(color: AppColors.white)),
          ),
        ],
      ),
    );
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
