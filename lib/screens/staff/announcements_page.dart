import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class StaffAnnouncementsPage extends StatelessWidget {
  const StaffAnnouncementsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Announcements'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: const Center(
        child: Text('This is the staff announcements page.'),
      ),
    );
  }
}
