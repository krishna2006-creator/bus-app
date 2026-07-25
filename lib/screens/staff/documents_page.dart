import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class StaffDocumentsPage extends StatelessWidget {
  const StaffDocumentsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Documents'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: const Center(
        child: Text('This is the staff documents page.'),
      ),
    );
  }
}
