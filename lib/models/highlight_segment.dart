import 'dart:io';

import 'clip_trim_mode.dart';

class HighlightSegment {
  const HighlightSegment({
    required this.id,
    required this.file,
    required this.sourcePath,
    required this.createdAt,
    required this.startOffset,
    required this.duration,
    this.redoCount = 0,
    this.frameRotationDegrees = 0,
    this.frameScale = 1,
    this.volume = 1,
    this.trimModeUsed,
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

  /// User-adjustable framing (画角) applied when trimming this segment from
  /// its source: rotation in degrees (any value, 1-degree granularity) and
  /// a zoom multiplier (1 = no zoom). Set via the clip framing editor.
  final double frameRotationDegrees;
  final double frameScale;

  /// This clip's own audio volume (0 = silent, 1 = original level, can go
  /// higher), mixed in independently of every other clip and of
  /// [HighlightReel.videoVolume] (which still applies as an overall
  /// multiplier on top).
  final double volume;

  /// Which [ClipTrimMode] was active when this segment was last cut from
  /// its source (initial add or a [HighlightReel.redo]) — shown in the clip
  /// list so it's clear how each clip came to be, even after the reel's
  /// current trim mode has since moved on. Null for segments predating this
  /// field.
  final ClipTrimMode? trimModeUsed;

  HighlightSegment copyWith({
    File? file,
    Duration? startOffset,
    Duration? duration,
    int? redoCount,
    double? frameRotationDegrees,
    double? frameScale,
    double? volume,
    ClipTrimMode? trimModeUsed,
  }) => HighlightSegment(
    id: id,
    file: file ?? this.file,
    sourcePath: sourcePath,
    createdAt: createdAt,
    startOffset: startOffset ?? this.startOffset,
    duration: duration ?? this.duration,
    redoCount: redoCount ?? this.redoCount,
    frameRotationDegrees: frameRotationDegrees ?? this.frameRotationDegrees,
    frameScale: frameScale ?? this.frameScale,
    volume: volume ?? this.volume,
    trimModeUsed: trimModeUsed ?? this.trimModeUsed,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'path': file.path,
    'sourcePath': sourcePath,
    'createdAt': createdAt.toIso8601String(),
    'startOffsetMs': startOffset.inMilliseconds,
    'durationMs': duration.inMilliseconds,
    'redoCount': redoCount,
    'frameRotationDegrees': frameRotationDegrees,
    'frameScale': frameScale,
    'volume': volume,
    'trimModeUsed': trimModeUsed?.name,
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
      frameRotationDegrees:
          (json['frameRotationDegrees'] as num?)?.toDouble() ?? 0,
      frameScale: (json['frameScale'] as num?)?.toDouble() ?? 1,
      volume: (json['volume'] as num?)?.toDouble() ?? 1,
      trimModeUsed: ClipTrimMode.values
          .where((m) => m.name == json['trimModeUsed'])
          .firstOrNull,
    );
  }
}
