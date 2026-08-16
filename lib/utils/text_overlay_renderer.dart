import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../models/app_font.dart';
import '../models/highlight_reel.dart';
import '../models/text_overlay.dart';

/// Renders [overlay]'s styled, rotated text directly to a PNG (via
/// [TextPainter] and a raw [ui.Canvas] — no widget tree/RepaintBoundary
/// needed) at its true reference-canvas resolution, saves it into [reel]'s
/// text-overlay directory, and returns [overlay] updated with the resulting
/// [TextOverlay.renderedImagePath]/width/height. Callers still need to
/// persist the result via [HighlightReel.upsertTextOverlay].
Future<TextOverlay> renderTextOverlay(
  TextOverlay overlay,
  HighlightReel reel,
) async {
  final font = AppFont.byId(overlay.fontId);
  final textStyle = TextStyle(
    fontFamily: font.familyName,
    fontSize: overlay.fontSize,
    color: overlay.color,
  );
  final painter = TextPainter(
    text: TextSpan(text: overlay.text, style: textStyle),
    textDirection: TextDirection.ltr,
  )..layout();

  const padding = 8.0;
  final textW = painter.width + padding * 2;
  final textH = painter.height + padding * 2;
  final angle = overlay.rotationDegrees * pi / 180;
  final boxW = (textW * cos(angle).abs() + textH * sin(angle).abs()).ceil();
  final boxH = (textW * sin(angle).abs() + textH * cos(angle).abs()).ceil();

  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(
    recorder,
    ui.Rect.fromLTWH(0, 0, boxW.toDouble(), boxH.toDouble()),
  );
  canvas.translate(boxW / 2, boxH / 2);
  canvas.rotate(angle);
  painter.paint(canvas, Offset(-painter.width / 2, -painter.height / 2));
  final picture = recorder.endRecording();
  final image = await picture.toImage(boxW, boxH);
  final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
  if (byteData == null) return overlay;

  final dir = await reel.textOverlayImagesDirectory();
  final file = File('${dir.path}/${overlay.id}.png');
  await file.writeAsBytes(byteData.buffer.asUint8List());

  return overlay.copyWith(
    renderedImagePath: file.path,
    renderedWidth: image.width,
    renderedHeight: image.height,
  );
}
