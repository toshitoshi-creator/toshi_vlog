import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:path_provider/path_provider.dart';

/// A rendered watermark PNG plus its pixel dimensions, needed to position it
/// (e.g. centering, or offsetting from a corner) when compositing.
class WatermarkImage {
  const WatermarkImage(this.file, this.width, this.height);

  final File file;
  final int width;
  final int height;
}

/// Renders the app's "AOK Craft" watermark text to a PNG, caching it at a
/// fixed path since it's static content with nothing per-caller to vary.
/// Re-rendered on every call (cheap — a few characters of text) rather than
/// checking the cache, so a future wording change always takes effect.
Future<WatermarkImage> renderWatermarkPng() async {
  const text = 'AOK Craft';
  const fontSize = 30.0;
  const padding = 10.0;

  final textStyle = TextStyle(
    fontSize: fontSize,
    color: const Color(0xE6FFFFFF),
    fontWeight: FontWeight.w600,
    shadows: const [Shadow(blurRadius: 5, color: Color(0xB3000000))],
  );
  final painter = TextPainter(
    text: TextSpan(text: text, style: textStyle),
    textDirection: TextDirection.ltr,
  )..layout();

  final width = (painter.width + padding * 2).ceil();
  final height = (painter.height + padding * 2).ceil();

  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(
    recorder,
    ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
  );
  painter.paint(canvas, const Offset(padding, padding));
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
  if (byteData == null) {
    throw Exception('watermark render failed');
  }

  final dir = await getApplicationDocumentsDirectory();
  final file = File('${dir.path}/watermark_aok_craft.png');
  await file.writeAsBytes(byteData.buffer.asUint8List());
  return WatermarkImage(file, width, height);
}
