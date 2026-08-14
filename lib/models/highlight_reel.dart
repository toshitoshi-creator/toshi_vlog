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
import 'saved_sound.dart';

/// Keeps a running "N seconds per clip" highlight reel: every time a full
/// recording is added, a window of it (length [clipDuration], chosen per
/// [trimMode]) is trimmed into a normalized segment file and the segments
/// are concatenated into a single compiled video. Segment order can be
/// edited manually, individual segments can be re-trimmed via [redo], and
/// clips can be removed.
class HighlightReel extends ChangeNotifier {
  List<HighlightSegment> _segments = [];
  File? _compiledFile;
  bool _isProcessing = false;
  String? _errorMessage;
  ClipTrimMode _trimMode = ClipTrimMode.random;
  Duration _clipDuration = const Duration(seconds: 1);
  final _random = Random();
  File? _bgmFile;
  String? _bgmTitle;

  List<HighlightSegment> get segments => List.unmodifiable(_segments);
  File? get compiledFile => _compiledFile;
  bool get isProcessing => _isProcessing;
  String? get errorMessage => _errorMessage;
  ClipTrimMode get trimMode => _trimMode;
  Duration get clipDuration => _clipDuration;
  File? get bgmFile => _bgmFile;
  String? get bgmTitle => _bgmTitle;

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
        final raw =
            jsonDecode(await settings.readAsString()) as Map<String, dynamic>;
        final modeName = raw['trimMode'] as String?;
        _trimMode = ClipTrimMode.values.firstWhere(
          (mode) => mode.name == modeName,
          orElse: () => ClipTrimMode.random,
        );
        final durationMs = raw['clipDurationMs'] as int?;
        if (durationMs != null && durationMs > 0) {
          _clipDuration = Duration(milliseconds: durationMs);
        }
        final bgmPath = raw['bgmPath'] as String?;
        if (bgmPath != null && File(bgmPath).existsSync()) {
          _bgmFile = File(bgmPath);
          _bgmTitle = raw['bgmTitle'] as String?;
        }
      } catch (_) {
        // Keep the defaults.
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
    await _persistSettings();
  }

  /// Changes the length of future clips. Already-added segments keep their
  /// original length until individually [redo]ne.
  Future<void> setClipDuration(Duration duration) async {
    if (_clipDuration == duration) return;
    _clipDuration = duration;
    notifyListeners();
    await _persistSettings();
  }

  /// Sets or clears the background music track mixed into the compiled
  /// video, replacing each clip's original audio. Pass `null` to remove it.
  Future<void> setBgm(SavedSound? sound) => _guarded(() async {
    _bgmFile = sound?.file;
    _bgmTitle = sound?.title;
    await _persistSettings();
    await _recompose();
  }, 'BGMの設定に失敗しました');

  Future<void> _persistSettings() async {
    final settings = await _settingsFile();
    await settings.writeAsString(
      jsonEncode({
        'trimMode': _trimMode.name,
        'clipDurationMs': _clipDuration.inMilliseconds,
        'bgmPath': _bgmFile?.path,
        'bgmTitle': _bgmTitle,
      }),
    );
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
    await _trimClip(sourceClip, outputFile, startOffset);

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

  /// Re-trims a segment using the current [trimMode]. For [ClipTrimMode.random]
  /// this naturally lands somewhere different each time; for
  /// [ClipTrimMode.loudest] it cycles to the next-loudest candidate window
  /// instead of repeating the same (loudest) one. A no-op for
  /// [ClipTrimMode.start].
  Future<void> redo(int index) => _guarded(() async {
    final segment = _segments[index];
    final source = File(segment.sourcePath);
    if (!await source.exists()) {
      throw Exception('元の動画が見つかりません');
    }
    final nextRedoCount = segment.redoCount + 1;
    final startOffset = await _computeStartOffset(source, rank: nextRedoCount);
    await _trimClip(source, segment.file, startOffset);

    _segments = [
      for (final s in _segments)
        if (s.id == segment.id) s.copyWith(redoCount: nextRedoCount) else s,
    ];
    await _persistManifest();
    await _recompose();
  }, 'クリップの作り直しに失敗しました');

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

  Future<Duration> _computeStartOffset(File source, {int rank = 0}) async {
    switch (_trimMode) {
      case ClipTrimMode.start:
        return Duration.zero;
      case ClipTrimMode.random:
        final duration = await _probeDuration(source);
        final maxStartMs = duration.inMilliseconds - _clipDuration.inMilliseconds;
        if (maxStartMs <= 0) return Duration.zero;
        return Duration(milliseconds: _random.nextInt(maxStartMs + 1));
      case ClipTrimMode.loudest:
        return _findLoudestOffset(source, rank);
    }
  }

  /// Samples mean volume across candidate windows (length [clipDuration])
  /// and returns the start offset of the [rank]-th loudest one (0 = loudest),
  /// wrapping around if [rank] exceeds the number of candidates. This is a
  /// cheap proxy for "an exciting moment" without needing on-device ML, and
  /// lets [redo] explore other loud spots instead of always finding the same
  /// single loudest one.
  Future<Duration> _findLoudestOffset(File source, int rank) async {
    final duration = await _probeDuration(source);
    final clipSeconds = _clipDuration.inMilliseconds / 1000;
    final maxStartSeconds = duration.inMilliseconds / 1000 - clipSeconds;
    if (maxStartSeconds <= 0) return Duration.zero;

    const maxSamples = 12;
    final totalWindows = (maxStartSeconds / clipSeconds).floor() + 1;
    final sampleCount = totalWindows < maxSamples ? totalWindows : maxSamples;
    final step = sampleCount <= 1 ? 0.0 : maxStartSeconds / (sampleCount - 1);

    final candidates = <MapEntry<double, double>>[];
    for (var i = 0; i < sampleCount; i++) {
      final offsetSeconds = sampleCount == 1 ? 0.0 : i * step;
      final volume =
          await _meanVolumeAt(source, offsetSeconds) ?? double.negativeInfinity;
      candidates.add(MapEntry(offsetSeconds, volume));
    }
    candidates.sort((a, b) => b.value.compareTo(a.value));
    final picked = candidates[rank % candidates.length];
    return Duration(milliseconds: (picked.key * 1000).round());
  }

  Future<double?> _meanVolumeAt(File source, double offsetSeconds) async {
    final session = await FFmpegKit.executeWithArguments([
      '-ss', offsetSeconds.toStringAsFixed(2),
      '-t', (_clipDuration.inMilliseconds / 1000).toStringAsFixed(2),
      '-i', source.path,
      '-af', 'volumedetect',
      '-f', 'null',
      '-',
    ]);
    final logs = await session.getAllLogsAsString() ?? '';
    final match =
        RegExp(r'mean_volume:\s*(-?\d+(\.\d+)?)\s*dB').firstMatch(logs);
    if (match == null) return null;
    return double.tryParse(match.group(1)!);
  }

  Future<void> _trimClip(
    File source,
    File output,
    Duration startOffset,
  ) async {
    final session = await FFmpegKit.executeWithArguments([
      '-y',
      '-ss', (startOffset.inMilliseconds / 1000).toStringAsFixed(2),
      '-i', source.path,
      '-t', (_clipDuration.inMilliseconds / 1000).toStringAsFixed(2),
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

    final concatOutput = File('${highlightsDir.path}/concat_raw.mp4');
    if (await concatOutput.exists()) {
      await concatOutput.delete();
    }

    final concatSession = await FFmpegKit.executeWithArguments([
      '-y',
      '-f', 'concat',
      '-safe', '0',
      '-i', listFile.path,
      '-c', 'copy',
      concatOutput.path,
    ]);
    if (!ReturnCode.isSuccess(await concatSession.getReturnCode())) {
      throw Exception('ffmpeg concat failed');
    }

    final tempOutput = File('${output.path}.tmp.mp4');
    if (await tempOutput.exists()) {
      await tempOutput.delete();
    }

    final bgm = _bgmFile;
    if (bgm != null && await bgm.exists()) {
      // Loops the BGM to cover the whole video and replaces each clip's
      // original audio with it, trimmed to the video's length.
      final muxSession = await FFmpegKit.executeWithArguments([
        '-y',
        '-i', concatOutput.path,
        '-stream_loop', '-1',
        '-i', bgm.path,
        '-map', '0:v:0',
        '-map', '1:a:0',
        '-c:v', 'copy',
        '-c:a', 'aac',
        '-shortest',
        tempOutput.path,
      ]);
      if (!ReturnCode.isSuccess(await muxSession.getReturnCode())) {
        throw Exception('ffmpeg bgm mux failed');
      }
    } else {
      await concatOutput.copy(tempOutput.path);
    }

    if (await output.exists()) {
      await output.delete();
    }
    await tempOutput.rename(output.path);
    _compiledFile = output;
  }
}
