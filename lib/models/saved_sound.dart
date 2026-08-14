import 'dart:io';

class SavedSound {
  const SavedSound({
    required this.id,
    required this.file,
    required this.title,
    required this.createdAt,
  });

  final String id;
  final File file;
  final String title;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => {
    'id': id,
    'path': file.path,
    'title': title,
    'createdAt': createdAt.toIso8601String(),
  };

  factory SavedSound.fromJson(Map<String, dynamic> json) => SavedSound(
    id: json['id'] as String,
    file: File(json['path'] as String),
    title: json['title'] as String,
    createdAt: DateTime.parse(json['createdAt'] as String),
  );
}
