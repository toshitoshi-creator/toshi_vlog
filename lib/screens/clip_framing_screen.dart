import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../models/highlight_reel.dart';
import '../models/highlight_segment.dart';

/// 画角編集 (framing) screen for a single clip: straighten/rotate in
/// 1-degree steps and zoom in around the center. Saving re-trims the
/// segment from its original source with the chosen framing baked in via
/// ffmpeg; the preview here is a live Flutter-side Transform over an
/// unframed extract of the clip so it's always an accurate WYSIWYG.
class ClipFramingScreen extends StatefulWidget {
  const ClipFramingScreen({
    super.key,
    required this.reel,
    required this.index,
    required this.segment,
  });

  final HighlightReel reel;
  final int index;
  final HighlightSegment segment;

  @override
  State<ClipFramingScreen> createState() => _ClipFramingScreenState();
}

class _ClipFramingScreenState extends State<ClipFramingScreen> {
  VideoPlayerController? _controller;
  String? _error;
  bool _isSaving = false;

  late double _rotation;
  late double _scale;

  @override
  void initState() {
    super.initState();
    _rotation = widget.segment.frameRotationDegrees;
    _scale = widget.segment.frameScale;
    _loadPreview();
  }

  Future<void> _loadPreview() async {
    try {
      final file = await widget.reel.extractUnframedPreview(widget.index);
      final controller = VideoPlayerController.file(file);
      await controller.initialize();
      await controller.setLooping(true);
      await controller.play();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() => _controller = controller);
    } catch (e) {
      if (mounted) setState(() => _error = 'プレビューを読み込めませんでした: $e');
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    await widget.reel.setSegmentFraming(
      widget.index,
      rotationDegrees: _rotation,
      scale: _scale,
    );
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  void _rotate90() {
    setState(() => _rotation = (_rotation + 90) % 360);
  }

  void _reset() {
    setState(() {
      _rotation = 0;
      _scale = 1;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('画角編集'),
        actions: [
          TextButton(
            onPressed: _reset,
            child: const Text('リセット'),
          ),
          IconButton(
            icon: _isSaving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check),
            tooltip: '保存',
            onPressed: _isSaving ? null : _save,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: AspectRatio(
                  aspectRatio:
                      HighlightReel.canvasWidth / HighlightReel.canvasHeight,
                  child: ClipRect(
                    child: Container(
                      color: Colors.black,
                      child: _controller != null &&
                              _controller!.value.isInitialized
                          ? Transform.rotate(
                              angle: _rotation * 3.1415926535 / 180,
                              child: Transform.scale(
                                scale: _scale,
                                child: FittedBox(
                                  fit: BoxFit.contain,
                                  child: SizedBox(
                                    width: _controller!.value.size.width,
                                    height: _controller!.value.size.height,
                                    child: VideoPlayer(_controller!),
                                  ),
                                ),
                              ),
                            )
                          : Center(
                              child: _error != null
                                  ? Padding(
                                      padding: const EdgeInsets.all(16),
                                      child: Text(
                                        _error!,
                                        style: const TextStyle(
                                          color: Colors.white70,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                    )
                                  : const CircularProgressIndicator(
                                      color: Colors.white,
                                    ),
                            ),
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: Column(
                children: [
                  Row(
                    children: [
                      Text('回転', style: Theme.of(context).textTheme.labelLarge),
                      const Spacer(),
                      Text('${_rotation.round()}°'),
                      IconButton(
                        icon: const Icon(Icons.rotate_right),
                        tooltip: '90度回転',
                        onPressed: _rotate90,
                      ),
                    ],
                  ),
                  Slider(
                    value: _rotation,
                    min: -180,
                    max: 180,
                    divisions: 360,
                    label: '${_rotation.round()}°',
                    onChanged: (v) => setState(() => _rotation = v),
                  ),
                  Row(
                    children: [
                      Text('拡大縮小', style: Theme.of(context).textTheme.labelLarge),
                      const Spacer(),
                      Text('${_scale.toStringAsFixed(2)}x'),
                    ],
                  ),
                  Slider(
                    value: _scale,
                    min: 1,
                    max: 3,
                    divisions: 40,
                    label: '${_scale.toStringAsFixed(2)}x',
                    onChanged: (v) => setState(() => _scale = v),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
