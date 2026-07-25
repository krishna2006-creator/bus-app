import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:photo_view/photo_view.dart';
import 'package:agni_college_bus_tracker/models/document.dart';

class FileViewerScreen extends StatelessWidget {
  final String filePath;
  final DocumentType fileType;

  const FileViewerScreen({
    super.key,
    required this.filePath,
    required this.fileType,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(filePath.split('/').last),
      ),
      body: _buildViewer(),
    );
  }

  Widget _buildViewer() {
    switch (fileType) {
      case DocumentType.image:
        return PhotoView(
          imageProvider: FileImage(File(filePath)),
        );
      case DocumentType.pdf:
        return PDFView(
          filePath: filePath,
        );
      case DocumentType.other:
        return const Center(
          child: Text('Unsupported file type'),
        );
    }
  }
}
