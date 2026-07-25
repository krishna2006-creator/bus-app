import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class StudentDocumentsPage extends StatelessWidget {
  const StudentDocumentsPage({super.key});

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
        child: Text('This is the student documents page.'),
      ),
    );
  }
}
