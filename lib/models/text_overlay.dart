import 'dart:ui';

/// A user-added caption on the まとめ動画. Position/rotation are stored
/// normalized to a 720x1280 reference canvas (matching the compiled video's
/// resolution), so they translate directly to output pixels regardless of
/// preview widget size. [renderedImagePath] is a PNG snapshot (already
/// rotated/styled by Flutter's own renderer) produced by the editor screen
/// and reused by [HighlightReel] to composite the caption via ffmpeg.
class TextOverlay {
  const TextOverlay({
    required this.id,
    required this.text,
    required this.fontId,
    required this.fontSize,
    required this.color,
    required this.x,
    required this.y,
    required this.rotationDegrees,
    required this.startClipIndex,
    required this.endClipIndex,
    this.renderedImagePath,
    this.renderedWidth,
    this.renderedHeight,
  });

  final String id;
  final String text;
  final String fontId;

  /// Font size in reference-canvas (720x1280) pixel units.
  final double fontSize;
  final Color color;

  /// Center position, normalized 0..1 across the reference canvas.
  final double x;
  final double y;
  final double rotationDegrees;

  /// Inclusive clip index range (0-based) this caption is visible for.
  final int startClipIndex;
  final int endClipIndex;

  final String? renderedImagePath;
  final int? renderedWidth;
  final int? renderedHeight;

  TextOverlay copyWith({
    String? text,
    String? fontId,
    double? fontSize,
    Color? color,
    double? x,
    double? y,
    double? rotationDegrees,
    int? startClipIndex,
    int? endClipIndex,
    String? renderedImagePath,
    int? renderedWidth,
    int? renderedHeight,
  }) {
    return TextOverlay(
      id: id,
      text: text ?? this.text,
      fontId: fontId ?? this.fontId,
      fontSize: fontSize ?? this.fontSize,
      color: color ?? this.color,
      x: x ?? this.x,
      y: y ?? this.y,
      rotationDegrees: rotationDegrees ?? this.rotationDegrees,
      startClipIndex: startClipIndex ?? this.startClipIndex,
      endClipIndex: endClipIndex ?? this.endClipIndex,
      renderedImagePath: renderedImagePath ?? this.renderedImagePath,
      renderedWidth: renderedWidth ?? this.renderedWidth,
      renderedHeight: renderedHeight ?? this.renderedHeight,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'text': text,
    'fontId': fontId,
    'fontSize': fontSize,
    'color': color.toARGB32(),
    'x': x,
    'y': y,
    'rotationDegrees': rotationDegrees,
    'startClipIndex': startClipIndex,
    'endClipIndex': endClipIndex,
    'renderedImagePath': renderedImagePath,
    'renderedWidth': renderedWidth,
    'renderedHeight': renderedHeight,
  };

  factory TextOverlay.fromJson(Map<String, dynamic> json) => TextOverlay(
    id: json['id'] as String,
    text: json['text'] as String,
    fontId: json['fontId'] as String,
    fontSize: (json['fontSize'] as num).toDouble(),
    color: Color(json['color'] as int),
    x: (json['x'] as num).toDouble(),
    y: (json['y'] as num).toDouble(),
    rotationDegrees: (json['rotationDegrees'] as num).toDouble(),
    startClipIndex: json['startClipIndex'] as int,
    endClipIndex: json['endClipIndex'] as int,
    renderedImagePath: json['renderedImagePath'] as String?,
    renderedWidth: json['renderedWidth'] as int?,
    renderedHeight: json['renderedHeight'] as int?,
  );
}
