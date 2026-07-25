import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class StaffRequestsPage extends StatelessWidget {
  const StaffRequestsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Requests'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: const Center(
        child: Text('This is the staff requests page.'),
      ),
    );
  }
}
