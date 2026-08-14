import 'dart:convert';
import 'dart:io';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'saved_sound.dart';

/// Manages audio tracks extracted from videos, so they can be reused as
/// background music for the highlight reel without depending on any
/// third-party music service (which would raise licensing issues for
/// audio baked into an exported video).
class SoundLibrary extends ChangeNotifier {
  List<SavedSound> _sounds = [];
  bool _isProcessing = false;
  String? _errorMessage;

  List<SavedSound> get sounds => List.unmodifiable(_sounds);
  bool get isProcessing => _isProcessing;
  String? get errorMessage => _errorMessage;

  Future<Directory> _soundsDirectory() async {
    final documentsDir = await getApplicationDocumentsDirectory();
    final dir = Directory('${documentsDir.path}/sounds');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<File> _manifestFile() async {
    final dir = await _soundsDirectory();
    return File('${dir.path}/manifest.json');
  }

  Future<void> load() async {
    try {
      final manifest = await _manifestFile();
      if (await manifest.exists()) {
        final raw =
            jsonDecode(await manifest.readAsString()) as List<dynamic>;
        _sounds = raw
            .map((e) => SavedSound.fromJson(e as Map<String, dynamic>))
            .where((sound) => sound.file.existsSync())
            .toList();
      }
    } catch (_) {
      _sounds = [];
    }
    notifyListeners();
  }

  Future<void> _persist() async {
    final manifest = await _manifestFile();
    await manifest.writeAsString(
      jsonEncode(_sounds.map((s) => s.toJson()).toList()),
    );
  }

  /// Extracts the audio track from [videoFile] and saves it as a new sound
  /// named [title]. [videoFile] is only read, never modified or deleted.
  Future<void> extractFromVideo(File videoFile, {required String title}) async {
    _isProcessing = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final dir = await _soundsDirectory();
      final id = DateTime.now().microsecondsSinceEpoch.toString();
      final output = File('${dir.path}/$id.m4a');
      final session = await FFmpegKit.executeWithArguments([
        '-y',
        '-i', videoFile.path,
        '-vn',
        '-c:a', 'aac',
        '-b:a', '192k',
        output.path,
      ]);
      final returnCode = await session.getReturnCode();
      if (!ReturnCode.isSuccess(returnCode)) {
        throw Exception('ffmpeg audio extraction failed');
      }
      _sounds = [
        ..._sounds,
        SavedSound(
          id: id,
          file: output,
          title: title,
          createdAt: DateTime.now(),
        ),
      ];
      await _persist();
    } catch (_) {
      _errorMessage = '音声の抽出に失敗しました(音声トラックがない可能性があります)';
    } finally {
      _isProcessing = false;
      notifyListeners();
    }
  }

  Future<void> delete(SavedSound sound) async {
    _sounds = [..._sounds]..removeWhere((s) => s.id == sound.id);
    if (await sound.file.exists()) {
      await sound.file.delete();
    }
    await _persist();
    notifyListeners();
  }
}
