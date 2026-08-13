import 'dart:io';

class HighlightSegment {
  const HighlightSegment({
    required this.id,
    required this.file,
    required this.sourcePath,
    required this.createdAt,
    this.redoCount = 0,
  });

  final String id;
  final File file;
  final String sourcePath;
  final DateTime createdAt;

  /// How many times this segment has been re-trimmed via [HighlightReel.redo].
  /// Used to cycle through alternative candidate windows (e.g. the
  /// next-loudest one) instead of repeatedly landing on the same spot.
  final int redoCount;

  HighlightSegment copyWith({int? redoCount}) => HighlightSegment(
    id: id,
    file: file,
    sourcePath: sourcePath,
    createdAt: createdAt,
    redoCount: redoCount ?? this.redoCount,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'path': file.path,
    'sourcePath': sourcePath,
    'createdAt': createdAt.toIso8601String(),
    'redoCount': redoCount,
  };

  factory HighlightSegment.fromJson(Map<String, dynamic> json) {
    return HighlightSegment(
      id: json['id'] as String,
      file: File(json['path'] as String),
      sourcePath: json['sourcePath'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      redoCount: json['redoCount'] as int? ?? 0,
    );
  }
}
