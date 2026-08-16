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
    required this.startSeconds,
    required this.endSeconds,
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

  /// Visible time range, in seconds from the start of the compiled video
  /// (before BGM/other overlays are applied). Freely chosen on a timeline,
  /// not snapped to clip boundaries.
  final double startSeconds;
  final double endSeconds;

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
    double? startSeconds,
    double? endSeconds,
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
      startSeconds: startSeconds ?? this.startSeconds,
      endSeconds: endSeconds ?? this.endSeconds,
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
    'startSeconds': startSeconds,
    'endSeconds': endSeconds,
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
    startSeconds: (json['startSeconds'] as num).toDouble(),
    endSeconds: (json['endSeconds'] as num).toDouble(),
    renderedImagePath: json['renderedImagePath'] as String?,
    renderedWidth: json['renderedWidth'] as int?,
    renderedHeight: json['renderedHeight'] as int?,
  );
}
