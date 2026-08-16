import 'dart:io';

class HighlightSegment {
  const HighlightSegment({
    required this.id,
    required this.file,
    required this.sourcePath,
    required this.createdAt,
    required this.startOffset,
    required this.duration,
    this.redoCount = 0,
  });

  final String id;
  final File file;
  final String sourcePath;
  final DateTime createdAt;

  /// Where in [sourcePath] this segment's window currently starts, and how
  /// long it is. Together they define exactly what [file] was trimmed from,
  /// so the editor timeline can adjust the trim (drag the clip's edges)
  /// without losing track of the source position.
  final Duration startOffset;
  final Duration duration;

  /// How many times this segment has been re-trimmed via [HighlightReel.redo].
  /// Used to cycle through alternative candidate windows (e.g. the
  /// next-loudest one) instead of repeatedly landing on the same spot.
  final int redoCount;

  HighlightSegment copyWith({
    File? file,
    Duration? startOffset,
    Duration? duration,
    int? redoCount,
  }) => HighlightSegment(
    id: id,
    file: file ?? this.file,
    sourcePath: sourcePath,
    createdAt: createdAt,
    startOffset: startOffset ?? this.startOffset,
    duration: duration ?? this.duration,
    redoCount: redoCount ?? this.redoCount,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'path': file.path,
    'sourcePath': sourcePath,
    'createdAt': createdAt.toIso8601String(),
    'startOffsetMs': startOffset.inMilliseconds,
    'durationMs': duration.inMilliseconds,
    'redoCount': redoCount,
  };

  factory HighlightSegment.fromJson(Map<String, dynamic> json) {
    return HighlightSegment(
      id: json['id'] as String,
      file: File(json['path'] as String),
      sourcePath: json['sourcePath'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      startOffset: Duration(milliseconds: json['startOffsetMs'] as int? ?? 0),
      duration: Duration(milliseconds: json['durationMs'] as int? ?? 0),
      redoCount: json['redoCount'] as int? ?? 0,
    );
  }
}
