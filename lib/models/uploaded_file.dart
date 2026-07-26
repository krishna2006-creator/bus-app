import 'package:agni_college_bus_tracker/config/app_config.dart';
import 'package:agni_college_bus_tracker/models/document.dart';

class UploadedFile {
  final String id;
  final String name;
  final String path;
  final DocumentType type;

  UploadedFile({
    required this.id,
    required this.name,
    required this.path,
    required this.type,
  });

  factory UploadedFile.fromJson(Map<String, dynamic> json) {
    return UploadedFile(
      id: json['id'] as String,
      name: json['name'] as String,
      path: json['path'] as String,
      type: DocumentType.values.byName(json['type'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'path': path,
        'type': type.name,
      };

  String get fileURL => '${AppConfig.baseUrl}/storage/$path';
}
