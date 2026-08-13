import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'clip_trim_mode.dart';
import 'highlight_segment.dart';

/// Keeps a running "1 second per clip" highlight reel: every time a full
/// recording is added, one second of it is trimmed (per [trimMode]) into a
/// normalized segment file and the segments are concatenated into a single
/// compiled video. Segment order can be edited manually and clips can be
/// removed.
class HighlightReel extends ChangeNotifier {
  List<HighlightSegment> _segments = [];
  File? _compiledFile;
  bool _isProcessing = false;
  String? _errorMessage;
  ClipTrimMode _trimMode = ClipTrimMode.random;
  final _random = Random();

  List<HighlightSegment> get segments => List.unmodifiable(_segments);
  File? get compiledFile => _compiledFile;
  bool get isProcessing => _isProcessing;
  String? get errorMessage => _errorMessage;
  ClipTrimMode get trimMode => _trimMode;

  Future<Directory> _highlightsDirectory() async {
    final documentsDir = await getApplicationDocumentsDirectory();
    final dir = Directory('${documentsDir.path}/highlights');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<Directory> _segmentsDirectory() async {
    final highlightsDir = await _highlightsDirectory();
    final dir = Directory('${highlightsDir.path}/segments');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<File> _manifestFile() async {
    final dir = await _highlightsDirectory();
    return File('${dir.path}/manifest.json');
  }

  Future<File> _settingsFile() async {
    final dir = await _highlightsDirectory();
    return File('${dir.path}/settings.json');
  }

  Future<File> _compiledOutputFile() async {
    final dir = await _highlightsDirectory();
    return File('${dir.path}/highlights.mp4');
  }

  Future<void> load() async {
    final manifest = await _manifestFile();
    if (await manifest.exists()) {
      try {
        final raw =
            jsonDecode(await manifest.readAsString()) as List<dynamic>;
        _segments = raw
            .map((e) => HighlightSegment.fromJson(e as Map<String, dynamic>))
            .where((segment) => segment.file.existsSync())
            .toList();
      } catch (_) {
        _segments = [];
      }
    }

    final settings = await _settingsFile();
    if (await settings.exists()) {
      try {
        final raw = jsonDecode(await settings.readAsString()) as Map<String, dynamic>;
        final modeName = raw['trimMode'] as String?;
        _trimMode = ClipTrimMode.values.firstWhere(
          (mode) => mode.name == modeName,
          orElse: () => ClipTrimMode.random,
        );
      } catch (_) {
        // Keep the default trim mode.
      }
    }

    final output = await _compiledOutputFile();
    _compiledFile = await output.exists() ? output : null;
    notifyListeners();
  }

  /// Changes how future clips are trimmed. Already-added segments are not
  /// re-trimmed retroactively.
  Future<void> setTrimMode(ClipTrimMode mode) async {
    if (_trimMode == mode) return;
    _trimMode = mode;
    notifyListeners();
    final settings = await _settingsFile();
    await settings.writeAsString(jsonEncode({'trimMode': mode.name}));
  }

  Future<void> _persistManifest() async {
    final manifest = await _manifestFile();
    final raw = jsonEncode(_segments.map((s) => s.toJson()).toList());
    await manifest.writeAsString(raw);
  }

  Future<void> addClip(File sourceClip) => _guarded(() async {
        final segmentsDir = await _segmentsDirectory();
        final id = DateTime.now().microsecondsSinceEpoch.toString();
        final outputFile = File('${segmentsDir.path}/$id.mp4');
        final startOffset = await _computeStartOffset(sourceClip);
        await _trimToOneSecond(sourceClip, outputFile, startOffset);

        _segments = [
          ..._segments,
          HighlightSegment(
            id: id,
            file: outputFile,
            sourcePath: sourceClip.path,
            createdAt: DateTime.now(),
          ),
        ];
        await _persistManifest();
        await _recompose();
      }, 'まとめ動画への追加に失敗しました');

  /// [newIndex] is the target index after [oldIndex] has been removed
  /// (i.e. as reported by [ReorderableListView]'s `onReorderItem`).
  Future<void> reorder(int oldIndex, int newIndex) => _guarded(() async {
        final updated = [..._segments];
        final item = updated.removeAt(oldIndex);
        updated.insert(newIndex, item);
        _segments = updated;
        await _persistManifest();
        await _recompose();
      }, 'まとめ動画の並び替えに失敗しました');

  Future<void> removeAt(int index) => _guarded(() async {
        final updated = [..._segments];
        final removed = updated.removeAt(index);
        _segments = updated;
        if (await removed.file.exists()) {
          await removed.file.delete();
        }
        await _persistManifest();
        await _recompose();
      }, 'まとめ動画の更新に失敗しました');

  Future<void> _guarded(
    Future<void> Function() action,
    String failureMessage,
  ) async {
    _isProcessing = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await action();
    } catch (_) {
      _errorMessage = failureMessage;
    } finally {
      _isProcessing = false;
      notifyListeners();
    }
  }

  Future<Duration> _probeDuration(File source) async {
    final session = await FFprobeKit.executeWithArguments([
      '-v', 'error',
      '-show_entries', 'format=duration',
      '-of', 'default=noprint_wrappers=1:nokey=1',
      source.path,
    ]);
    final output = (await session.getOutput())?.trim();
    final seconds = double.tryParse(output ?? '') ?? 0;
    if (!seconds.isFinite || seconds <= 0) return Duration.zero;
    return Duration(milliseconds: (seconds * 1000).round());
  }

  Future<Duration> _computeStartOffset(File source) async {
    switch (_trimMode) {
      case ClipTrimMode.start:
        return Duration.zero;
      case ClipTrimMode.random:
        final duration = await _probeDuration(source);
        final maxStartMs = duration.inMilliseconds - 1000;
        if (maxStartMs <= 0) return Duration.zero;
        return Duration(milliseconds: _random.nextInt(maxStartMs + 1));
      case ClipTrimMode.loudest:
        return _findLoudestOffset(source);
    }
  }

  /// Samples mean volume across candidate 1-second windows and returns the
  /// start offset of the loudest one, as a cheap proxy for "an exciting
  /// moment" without needing on-device ML.
  Future<Duration> _findLoudestOffset(File source) async {
    final duration = await _probeDuration(source);
    final maxStartSeconds = duration.inMilliseconds / 1000 - 1;
    if (maxStartSeconds <= 0) return Duration.zero;

    const maxSamples = 12;
    final totalWholeSeconds = maxStartSeconds.floor();
    final sampleCount = totalWholeSeconds < maxSamples
        ? totalWholeSeconds + 1
        : maxSamples;
    final step = sampleCount <= 1
        ? 0.0
        : maxStartSeconds / (sampleCount - 1);

    var bestOffsetSeconds = 0.0;
    var bestVolume = double.negativeInfinity;

    for (var i = 0; i < sampleCount; i++) {
      final offsetSeconds = sampleCount == 1 ? 0.0 : i * step;
      final volume = await _meanVolumeAt(source, offsetSeconds);
      if (volume != null && volume > bestVolume) {
        bestVolume = volume;
        bestOffsetSeconds = offsetSeconds;
      }
    }

    return Duration(milliseconds: (bestOffsetSeconds * 1000).round());
  }

  Future<double?> _meanVolumeAt(File source, double offsetSeconds) async {
    final session = await FFmpegKit.executeWithArguments([
      '-ss', offsetSeconds.toStringAsFixed(2),
      '-t', '1',
      '-i', source.path,
      '-af', 'volumedetect',
      '-f', 'null',
      '-',
    ]);
    final logs = await session.getAllLogsAsString() ?? '';
    final match = RegExp(r'mean_volume:\s*(-?\d+(\.\d+)?)\s*dB').firstMatch(logs);
    if (match == null) return null;
    return double.tryParse(match.group(1)!);
  }

  Future<void> _trimToOneSecond(
    File source,
    File output,
    Duration startOffset,
  ) async {
    final session = await FFmpegKit.executeWithArguments([
      '-y',
      '-ss', (startOffset.inMilliseconds / 1000).toStringAsFixed(2),
      '-i', source.path,
      '-t', '1',
      '-vf',
      'scale=w=720:h=1280:force_original_aspect_ratio=decrease,'
          'pad=720:1280:(ow-iw)/2:(oh-ih)/2,setsar=1',
      '-r', '30',
      '-c:v', 'libx264',
      '-preset', 'veryfast',
      '-c:a', 'aac',
      '-ar', '44100',
      '-ac', '2',
      output.path,
    ]);
    final returnCode = await session.getReturnCode();
    if (!ReturnCode.isSuccess(returnCode)) {
      throw Exception('ffmpeg trim failed');
    }
  }

  Future<void> _recompose() async {
    final output = await _compiledOutputFile();

    if (_segments.isEmpty) {
      if (await output.exists()) {
        await output.delete();
      }
      _compiledFile = null;
      return;
    }

    final highlightsDir = await _highlightsDirectory();
    final listFile = File('${highlightsDir.path}/concat_list.txt');
    final buffer = StringBuffer();
    for (final segment in _segments) {
      final escapedPath = segment.file.path.replaceAll("'", r"'\''");
      buffer.writeln("file '$escapedPath'");
    }
    await listFile.writeAsString(buffer.toString());

    final tempOutput = File('${output.path}.tmp.mp4');
    if (await tempOutput.exists()) {
      await tempOutput.delete();
    }

    final session = await FFmpegKit.executeWithArguments([
      '-y',
      '-f', 'concat',
      '-safe', '0',
      '-i', listFile.path,
      '-c', 'copy',
      tempOutput.path,
    ]);
    final returnCode = await session.getReturnCode();
    if (!ReturnCode.isSuccess(returnCode)) {
      throw Exception('ffmpeg concat failed');
    }

    if (await output.exists()) {
      await output.delete();
    }
    await tempOutput.rename(output.path);
    _compiledFile = output;
  }
}
