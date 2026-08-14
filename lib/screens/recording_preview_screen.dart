import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// Shows the just-recorded clip and lets the user choose to keep it or
/// retake. Pops with `true` (save) or `false` (discard/retake).
class RecordingPreviewScreen extends StatefulWidget {
  const RecordingPreviewScreen({super.key, required this.file});

  final File file;

  @override
  State<RecordingPreviewScreen> createState() =>
      _RecordingPreviewScreenState();
}

class _RecordingPreviewScreenState extends State<RecordingPreviewScreen> {
  late final VideoPlayerController _controller;
  bool _isReady = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.file(widget.file);
    _controller.initialize().then((_) {
      if (!mounted) return;
      setState(() => _isReady = true);
      _controller
        ..setLooping(true)
        ..play();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) Navigator.of(context).pop(false);
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: Center(
                  child: _isReady
                      ? AspectRatio(
                          aspectRatio: _controller.value.aspectRatio,
                          child: VideoPlayer(_controller),
                        )
                      : const CircularProgressIndicator(color: Colors.white),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(24),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 14,
                        ),
                      ),
                      onPressed: () => Navigator.of(context).pop(false),
                      icon: const Icon(Icons.replay),
                      label: const Text('撮り直す'),
                    ),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 14,
                        ),
                      ),
                      onPressed: () => Navigator.of(context).pop(true),
                      icon: const Icon(Icons.check),
                      label: const Text('保存'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
