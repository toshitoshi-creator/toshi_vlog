import 'dart:io';

class HighlightSegment {
  const HighlightSegment({
    required this.id,
    required this.file,
    required this.sourcePath,
    required this.createdAt,
  });

  final String id;
  final File file;
  final String sourcePath;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'path': file.path,
        'sourcePath': sourcePath,
        'createdAt': createdAt.toIso8601String(),
      };

  factory HighlightSegment.fromJson(Map<String, dynamic> json) {
    return HighlightSegment(
      id: json['id'] as String,
      file: File(json['path'] as String),
      sourcePath: json['sourcePath'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }
}
