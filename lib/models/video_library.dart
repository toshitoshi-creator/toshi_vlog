import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

import 'video_item.dart';

class VideoLibrary extends ChangeNotifier {
  List<VideoItem> _videos = [];

  List<VideoItem> get videos => List.unmodifiable(_videos);

  Future<Directory> _videosDirectory() async {
    final documentsDir = await getApplicationDocumentsDirectory();
    final videosDir = Directory('${documentsDir.path}/videos');
    if (!await videosDir.exists()) {
      await videosDir.create(recursive: true);
    }
    return videosDir;
  }

  Future<void> reload() async {
    final dir = await _videosDirectory();
    final files = await dir
        .list()
        .where((entity) => entity is File && entity.path.endsWith('.mp4'))
        .cast<File>()
        .toList();

    final items = <VideoItem>[];
    for (final file in files) {
      final stat = await file.stat();
      final duration = await _readDuration(file);
      items.add(VideoItem(
        file: file,
        createdAt: stat.modified,
        duration: duration,
      ));
    }
    items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    _videos = items;
    notifyListeners();
  }

  Future<Duration> _readDuration(File file) async {
    final controller = VideoPlayerController.file(file);
    try {
      await controller.initialize();
      return controller.value.duration;
    } catch (_) {
      return Duration.zero;
    } finally {
      await controller.dispose();
    }
  }

  Future<File> store(String temporaryPath) async {
    final dir = await _videosDirectory();
    final fileName = '${DateTime.now().microsecondsSinceEpoch}.mp4';
    final source = File(temporaryPath);
    final destination = File('${dir.path}/$fileName');
    await source.copy(destination.path);
    await source.delete();
    await reload();
    return destination;
  }

  Future<void> delete(VideoItem item) async {
    if (await item.file.exists()) {
      await item.file.delete();
    }
    await reload();
  }
}
