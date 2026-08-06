import 'dart:io';

class VideoItem {
  const VideoItem({
    required this.file,
    required this.createdAt,
    required this.duration,
  });

  final File file;
  final DateTime createdAt;
  final Duration duration;
}
