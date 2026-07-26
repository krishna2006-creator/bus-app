import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:agni_college_bus_tracker/services/file_service.dart';
import 'package:agni_college_bus_tracker/services/auth_service.dart';
import 'package:agni_college_bus_tracker/models/document.dart';
import 'package:agni_college_bus_tracker/models/uploaded_file.dart';
import 'package:agni_college_bus_tracker/models/user.dart';
import 'package:agni_college_bus_tracker/theme.dart';

// Documents page to display and manage files
class DocumentsPage extends StatefulWidget {
  const DocumentsPage({super.key});

  @override
  State<DocumentsPage> createState() => _DocumentsPageState();
}

class _DocumentsPageState extends State<DocumentsPage> {
  @override
  void initState() {
    super.initState();
    // Sync documents from backend on page load
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<FileService>().refreshDocuments();
    });
  }

  @override
  Widget build(BuildContext context) {
    final fileService = context.watch<FileService>();
    final authService = context.watch<AuthService>();
    final user = authService.currentUser;
    // Allow Admins, Staff, and Drivers to delete documents
    final canDelete = user?.role == UserRole.admin ||
        user?.role == UserRole.staff ||
        user?.role == UserRole.driver;
    final isAdmin = user?.role == UserRole.admin;

    final files = fileService.files;
    final isLoading = fileService.isLoadingFromBackend;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Documents'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              fileService.refreshDocuments();
            },
          ),
        ],
      ),
      body: isLoading
          ? const Center(
              child: CircularProgressIndicator(),
            )
          : files.isEmpty
              ? const Center(
                  child: Text('No documents have been uploaded yet.'),
                )
              : ListView.builder(
                  itemCount: files.length,
                  itemBuilder: (context, index) {
                    final file = files[index];
                    return Card(
                      child: ListTile(
                        leading: Icon(_getIconForFileType(file.type)),
                        title: Text(file.name),
                        subtitle: file.path.startsWith('/')
                            ? const Text('(From server)')
                            : null,
                        onTap: () => fileService.openFile(context, file),
                        trailing: canDelete
                            ? IconButton(
                                icon: const Icon(Icons.delete,
                                    color: AppColors.error),
                                onPressed: () =>
                                    _confirmDelete(context, fileService, file),
                              )
                            : null,
                      ),
                    );
                  },
                ),
      floatingActionButton: isAdmin
          ? FloatingActionButton(
              onPressed: () => fileService.addFile(),
              child: const Icon(Icons.add),
            )
          : null,
    );
  }

  IconData _getIconForFileType(DocumentType type) {
    switch (type) {
      case DocumentType.image:
        return Icons.image;
      case DocumentType.pdf:
        return Icons.picture_as_pdf;
      case DocumentType.other:
        return Icons.insert_drive_file;
    }
  }

  void _confirmDelete(
      BuildContext context, FileService fileService, UploadedFile file) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Confirm Delete'),
          content: Text('Are you sure you want to delete ${file.name}?'),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: const Text('Delete', style: TextStyle(color: Colors.red)),
              onPressed: () {
                fileService.deleteFile(file.id);
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }
}
