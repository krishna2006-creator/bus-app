import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:agni_college_bus_tracker/services/file_service.dart';

class ShareDocumentPage extends StatefulWidget {
  const ShareDocumentPage({super.key});

  @override
  State<ShareDocumentPage> createState() => _ShareDocumentPageState();
}

class _ShareDocumentPageState extends State<ShareDocumentPage> {
  final _formKey = GlobalKey<FormState>();
  String _title = '';
  String _description = '';
  PlatformFile? _file;

  void _pickFile() async {
    final result = await context.read<FileService>().pickFile();
    if (result != null) {
      setState(() {
        _file = result;
      });
    }
  }

  void _submit() {
    if (_formKey.currentState!.validate()) {
      _formKey.currentState!.save();
      if (_file != null) {
        context.read<FileService>().uploadFile(
              _file!,
              _title,
              _description,
            );
        context.pop();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select a file to share.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Share Document'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(
                decoration: const InputDecoration(labelText: 'Title'),
                validator: (value) =>
                    value!.isEmpty ? 'Please enter a title' : null,
                onSaved: (value) => _title = value!,
              ),
              TextFormField(
                decoration: const InputDecoration(labelText: 'Description'),
                onSaved: (value) => _description = value!,
              ),
              const SizedBox(height: 20),
              _file == null
                  ? const Text('No file selected.')
                  : Text('Selected file: ${_file!.name}'),
              ElevatedButton(
                onPressed: _pickFile,
                child: const Text('Select File'),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _submit,
                child: const Text('Share'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
