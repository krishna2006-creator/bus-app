import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:agni_college_bus_tracker/models/document.dart';
import 'package:agni_college_bus_tracker/models/uploaded_file.dart';
import 'package:agni_college_bus_tracker/models/user.dart';
import 'package:agni_college_bus_tracker/services/notification_service.dart';
import 'package:agni_college_bus_tracker/services/api_service.dart';
import 'package:go_router/go_router.dart';

// File service for handling file operations
class FileService extends ChangeNotifier {
  static const _filesKey = 'files';

  List<UploadedFile> _files = [];
  bool _isLoadingFromBackend = false;

  FileService(NotificationService notificationService);

  List<UploadedFile> get files => _files;
  bool get isLoadingFromBackend => _isLoadingFromBackend;

  Future<void> initialize() async {
    // First try to load from backend
    await _syncDocumentsFromBackend();

    // Only use local storage as fallback if backend returned no data
    if (_files.isEmpty) {
      final prefs = await SharedPreferences.getInstance();
      final filesJson = prefs.getStringList(_filesKey) ?? [];
      if (filesJson.isNotEmpty) {
        _files =
            filesJson.map((f) => UploadedFile.fromJson(jsonDecode(f))).toList();
      }
    }
    notifyListeners();
  }

  Future<void> _syncDocumentsFromBackend() async {
    try {
      _isLoadingFromBackend = true;
      notifyListeners();

      final response = await http.get(
        Uri.parse('${ApiService.baseUrl}/documents'),
        headers: await ApiService.getHeaders(),
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        _files = data.map((doc) {
          // Backend returns id as int, convert to String
          final docId = doc['id']?.toString() ?? '';
          return UploadedFile(
            id: docId,
            name: doc['name'] ?? '',
            path: doc['url'] ?? '',
            type: _parseDocumentType(doc['file_type'] ?? 'other'),
          );
        }).toList();

        await _saveFiles();
      }
    } catch (e) {
      debugPrint('Error syncing documents from backend: $e');
    } finally {
      _isLoadingFromBackend = false;
      notifyListeners();
    }
  }

  DocumentType _parseDocumentType(String fileType) {
    switch (fileType.toLowerCase()) {
      case 'pdf':
        return DocumentType.pdf;
      case 'image':
        return DocumentType.image;
      default:
        return DocumentType.other;
    }
  }

  Future<void> _saveFiles() async {
    final prefs = await SharedPreferences.getInstance();
    final filesJson = _files.map((f) => jsonEncode(f.toJson())).toList();
    await prefs.setStringList(_filesKey, filesJson);
  }

  Future<void> _uploadFileToBackend(String filePath, String name) async {
    try {
      final token = await ApiService.getToken();
      final url = Uri.parse('${ApiService.baseUrl}/documents/upload');
      final request = http.MultipartRequest('POST', url);
      request.headers.addAll({
        if (token != null) 'Authorization': 'Bearer $token',
      });
      request.fields['name'] = name;
      request.files.add(await http.MultipartFile.fromPath(
        'file',
        filePath,
      ));
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);
      if (response.statusCode == 200 || response.statusCode == 201) {
        debugPrint('File uploaded successfully to backend');
      } else {
        debugPrint(
            'Failed to upload file to backend: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      debugPrint('Error uploading file to backend: $e');
    }
  }

  Future<void> addFile({List<User>? allUsers}) async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf'],
      );

      if (result != null) {
        final pickedFile = result.files.single;
        if (pickedFile.path != null) {
          await _uploadFileToBackend(pickedFile.path!, pickedFile.name);
          await refreshDocuments();
        }
      }
    } catch (e) {
      debugPrint('Error adding file: $e');
    }
  }

  Future<PlatformFile?> pickFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles();
    if (result != null) {
      return result.files.first;
    }
    return null;
  }

  Future<void> uploadFile(
      PlatformFile file, String title, String description) async {
    try {
      if (file.path != null) {
        await _uploadFileToBackend(file.path!, title);
        await refreshDocuments();
      }
    } catch (e) {
      debugPrint('Error uploading file: $e');
    }
  }

  Future<void> openFile(BuildContext context, UploadedFile file) async {
    // If file is from backend (starts with /), open directly via URL
    if (file.path.startsWith('/')) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(),
        ),
      );

      try {
        final baseUrlWithoutApi = ApiService.baseUrl.replaceAll('/api', '');
        final fullUrl = '$baseUrlWithoutApi${file.path}';

        final response = await http.get(Uri.parse(fullUrl));

        if (context.mounted) {
          Navigator.of(context).pop(); // Dismiss loading indicator
        }

        if (response.statusCode == 200) {
          final tempDir = await getTemporaryDirectory();
          final tempFile = File('${tempDir.path}/${file.name}');
          await tempFile.writeAsBytes(response.bodyBytes);

          if (context.mounted) {
            context.push('/file-viewer',
                extra: UploadedFile(
                  id: file.id,
                  name: file.name,
                  path: tempFile.path,
                  type: file.type,
                ));
          }
        } else {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                  content:
                      Text('Failed to download file: ${response.statusCode}')),
            );
          }
        }
      } catch (e) {
        if (context.mounted) {
          Navigator.of(context).pop(); // Dismiss loading indicator
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error downloading file: $e')),
          );
        }
      }
    } else {
      // Local file
      context.push('/file-viewer', extra: file);
    }
  }

  // Periodic sync - call this periodically from main app
  Future<void> refreshDocuments() async {
    await _syncDocumentsFromBackend();
  }

  Future<void> deleteFile(String id) async {
    try {
      // Call backend API to delete document
      try {
        final response = await http.delete(
          Uri.parse('${ApiService.baseUrl}/documents/$id'),
          headers: await ApiService.getHeaders(),
        );
        if (response.statusCode == 200) {
          debugPrint('Document deleted from backend successfully');
        } else {
          debugPrint(
              'Backend delete failed: ${response.statusCode} - ${response.body}');
        }
      } catch (e) {
        debugPrint('Error deleting from backend: $e');
      }

      _files.removeWhere((f) => f.id == id);
      await _saveFiles();
      notifyListeners();
    } catch (e) {
      debugPrint('Error deleting file: $e');
    }
  }
}
