import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../utils/watermark_renderer.dart';
import 'clip_trim_mode.dart';
import 'export_settings.dart';
import 'highlight_segment.dart';
import 'saved_sound.dart';
import 'text_overlay.dart';

/// Keeps a running "N seconds per clip" highlight reel: every time a full
/// recording is added, a window of it (length [clipDuration], chosen per
/// [trimMode]) is trimmed into a normalized segment file and the segments
/// are concatenated into a single compiled video. Segment order can be
/// edited manually, individual segments can be re-trimmed via [redo], and
/// clips can be removed.
class HighlightReel extends ChangeNotifier {
  /// [id] selects this reel's storage directory. `'current'` is the
  /// always-existing, currently-being-built まとめ動画 and keeps the
  /// original fixed path for backward compatibility with existing installs;
  /// any other id is a saved snapshot living under its own subdirectory (see
  /// [CompilationLibrary]).
  HighlightReel({this.id = 'current'});

  final String id;

  /// The compiled video's fixed resolution; text overlay positions/sizes
  /// are normalized against this so the editor preview and the ffmpeg
  /// export agree regardless of the preview widget's on-screen size.
  static const canvasWidth = 720;
  static const canvasHeight = 1280;

  List<HighlightSegment> _segments = [];
  File? _compiledFile;

  /// Clips + BGM/volume mixed in, but with no captions or opening baked
  /// in — what the 編集 tab's live preview actually plays, so captions can
  /// be rendered purely as Flutter widgets without ever duplicating a
  /// burned-in copy of themselves. [compiledFile] (captions and opening
  /// included) is what gets downloaded/exported.
  File? _previewFile;
  bool _isProcessing = false;
  String? _errorMessage;
  ClipTrimMode _trimMode = ClipTrimMode.random;
  Duration _clipDuration = const Duration(seconds: 1);
  final _random = Random();
  File? _bgmFile;
  String? _bgmTitle;
  double _bgmVolume = 1;
  double _videoVolume = 1;

  /// Where in the video's own timeline the BGM starts playing, and where it
  /// stops (null = plays through to the end of the video). Only meaningful
  /// once [bgmFile] is set; the 編集 tab's timeline shows/edits this as a
  /// draggable bar, while 簡易編集's simpler BGM picker never touches it,
  /// leaving new tracks spanning the whole video by default.
  double _bgmStartSeconds = 0;
  double? _bgmEndSeconds;
  List<TextOverlay> _textOverlays = [];
  ExportResolution _exportResolution = ExportResolution.hd;
  int _exportFps = 30;

  /// Whether the export prepends an "opening" built from the middle 1
  /// second of each clip's source recording. Only meaningful/settable once
  /// there are at least [minClipsForOpening] segments.
  bool _includeOpening = false;
  static const minClipsForOpening = 4;

  /// Cache for [_buildOpeningIfNeeded] — rebuilding it means re-encoding
  /// one clip per segment, so it's skipped whenever nothing about the
  /// segments (order, trim, framing) has actually changed since the last
  /// [_recompose] (e.g. an unrelated caption/BGM/volume edit).
  File? _cachedOpeningFile;
  String? _cachedOpeningFingerprint;

  /// Whether 簡易編集's daily auto-clear (see [applyDailyAutoClear]) is
  /// allowed to skip clearing this reel. Only actually takes effect for a
  /// premium user — a lapsed subscription falls back to the default
  /// (always clears) regardless of this stored value. Irrelevant to any
  /// reel other than `current`, which is the only one auto-clear ever runs
  /// against.
  bool _autoClearEnabled = true;
  static const _autoClearAfter = Duration(hours: 24);

  /// Bumped every time [_recompose] actually rewrites [compiledFile]'s
  /// contents. The output path never changes between recompositions, so
  /// callers that cache a player/controller for [compiledFile] should
  /// compare this instead of the path to notice new content.
  int _revision = 0;

  List<HighlightSegment> get segments => List.unmodifiable(_segments);
  File? get compiledFile => _compiledFile;
  File? get previewFile => _previewFile;
  bool get isProcessing => _isProcessing;
  String? get errorMessage => _errorMessage;
  ClipTrimMode get trimMode => _trimMode;
  Duration get clipDuration => _clipDuration;
  File? get bgmFile => _bgmFile;
  String? get bgmTitle => _bgmTitle;
  double get bgmVolume => _bgmVolume;
  double get videoVolume => _videoVolume;
  double get bgmStartSeconds => _bgmStartSeconds;
  double? get bgmEndSeconds => _bgmEndSeconds;
  bool get autoClearEnabled => _autoClearEnabled;

  /// The video's current total duration in seconds, used to resolve a null
  /// [bgmEndSeconds] (BGM plays to the end) to a concrete value for display.
  double get totalSeconds =>
      _segments.fold<int>(0, (sum, s) => sum + s.duration.inMilliseconds) /
      1000;
  List<TextOverlay> get textOverlays => List.unmodifiable(_textOverlays);
  int get revision => _revision;
  ExportResolution get exportResolution => _exportResolution;
  int get exportFps => _exportFps;
  bool get includeOpening => _includeOpening;
  bool get canIncludeOpening => _segments.length >= minClipsForOpening;

  Future<Directory> _highlightsDirectory() async {
    final documentsDir = await getApplicationDocumentsDirectory();
    final dir = id == 'current'
        ? Directory('${documentsDir.path}/highlights')
        : Directory('${documentsDir.path}/compilations/$id');
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

  /// Directory for text-overlay PNG snapshots rendered by the editor.
  Future<Directory> textOverlayImagesDirectory() async {
    final highlightsDir = await _highlightsDirectory();
    final dir = Directory('${highlightsDir.path}/text_overlays');
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

  Future<File> _textOverlaysFile() async {
    final dir = await _highlightsDirectory();
    return File('${dir.path}/text_overlays.json');
  }

  Future<File> _compiledOutputFile() async {
    final dir = await _highlightsDirectory();
    return File('${dir.path}/highlights.mp4');
  }

  Future<void> load() async {
    final manifest = await _manifestFile();
    if (await manifest.exists()) {
      try {
        final raw = jsonDecode(await manifest.readAsString()) as List<dynamic>;
        _segments = raw
            .map((e) => HighlightSegment.fromJson(e as Map<String, dynamic>))
            .where((segment) => segment.file.existsSync())
            .toList();
      } catch (_) {
        _segments = [];
      }
    }

    // Segments saved before startOffset/duration were tracked come back
    // with duration == Duration.zero; probe the actual trimmed file once to
    // backfill them so the editor timeline has real lengths to lay out.
    if (_segments.any((s) => s.duration == Duration.zero)) {
      final backfilled = <HighlightSegment>[];
      for (final segment in _segments) {
        if (segment.duration == Duration.zero) {
          final probed = await _probeDuration(segment.file);
          backfilled.add(
            segment.copyWith(duration: probed, startOffset: Duration.zero),
          );
        } else {
          backfilled.add(segment);
        }
      }
      _segments = backfilled;
      await _persistManifest();
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
        _bgmVolume = (raw['bgmVolume'] as num?)?.toDouble() ?? 1;
        _videoVolume = (raw['videoVolume'] as num?)?.toDouble() ?? 1;
        _bgmStartSeconds = (raw['bgmStartSeconds'] as num?)?.toDouble() ?? 0;
        _bgmEndSeconds = (raw['bgmEndSeconds'] as num?)?.toDouble();
        _exportResolution = ExportResolution.fromName(
          raw['exportResolution'] as String?,
        );
        _exportFps = raw['exportFps'] as int? ?? 30;
        _includeOpening = raw['includeOpening'] as bool? ?? false;
        _autoClearEnabled = raw['autoClearEnabled'] as bool? ?? true;
      } catch (_) {
        // Keep the defaults.
      }
    }

    final textOverlaysFile = await _textOverlaysFile();
    if (await textOverlaysFile.exists()) {
      try {
        final raw =
            jsonDecode(await textOverlaysFile.readAsString()) as List<dynamic>;
        _textOverlays = raw
            .map((e) => TextOverlay.fromJson(e as Map<String, dynamic>))
            .toList();
      } catch (_) {
        _textOverlays = [];
      }
    }

    final output = await _compiledOutputFile();
    _compiledFile = await output.exists() ? output : null;
    final highlightsDir = await _highlightsDirectory();
    final preview = File('${highlightsDir.path}/preview.mp4');
    _previewFile = await preview.exists() ? preview : null;
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
  /// video alongside each clip's original audio (see [setVolumes] for
  /// their relative levels). Pass `null` to remove it.
  Future<void> setBgm(SavedSound? sound) => _guarded(() async {
    _bgmFile = sound?.file;
    _bgmTitle = sound?.title;
    // A newly picked track's old placement wouldn't make sense against a
    // different track, so reset to "spans the whole video" — also what
    // 簡易編集's insertion-only picker relies on, since it never calls
    // setBgmTiming at all.
    _bgmStartSeconds = 0;
    _bgmEndSeconds = null;
    await _persistSettings();
    await _recompose();
  }, 'BGMの設定に失敗しました');

  /// Adjusts where in the video's timeline the BGM plays, as dragged on the
  /// 編集 tab's timeline. [end] of `null` means "through to the end of the
  /// video". No-ops if there's no BGM set.
  Future<void> setBgmTiming(double start, double? end) => _guarded(() async {
    if (_bgmFile == null) return;
    _bgmStartSeconds = start;
    _bgmEndSeconds = end;
    await _persistSettings();
    await _recompose();
  }, 'BGMのタイミング設定に失敗しました');

  /// Sets the mix volume (0 = silent, 1 = original level, can go higher)
  /// for the BGM track and/or the clips' own recorded audio. Pass `null`
  /// to leave either side unchanged.
  Future<void> setVolumes({double? bgmVolume, double? videoVolume}) =>
      _guarded(() async {
        if (bgmVolume != null) _bgmVolume = bgmVolume;
        if (videoVolume != null) _videoVolume = videoVolume;
        await _persistSettings();
        await _recompose();
      }, '音量の設定に失敗しました');

  /// Sets the compiled video's export resolution/frame rate. Pass `null`
  /// to leave either unchanged.
  Future<void> setExportSettings({ExportResolution? resolution, int? fps}) =>
      _guarded(() async {
        if (resolution != null) _exportResolution = resolution;
        if (fps != null) _exportFps = fps;
        await _persistSettings();
        await _recompose();
      }, '書き出し設定の変更に失敗しました');

  /// Toggles prepending an opening (built from the middle 1 second of each
  /// clip's source) before the main video on export. No-ops if there
  /// aren't enough clips yet (see [canIncludeOpening]).
  Future<void> setIncludeOpening(bool value) => _guarded(() async {
    if (value && !canIncludeOpening) return;
    _includeOpening = value;
    await _persistSettings();
    await _recompose();
  }, 'オープニング設定の変更に失敗しました');

  /// Premium-only in practice: [applyDailyAutoClear] only honors this when
  /// the caller is currently premium, so a free user flipping it has no
  /// effect (the UI is expected to gate this behind a paywall check
  /// itself, same as export resolution/fps).
  Future<void> setAutoClearEnabled(bool value) => _guarded(() async {
    _autoClearEnabled = value;
    await _persistSettings();
  }, '自動削除設定の変更に失敗しました');

  /// Resets this reel back to empty — clips, captions, and the BGM
  /// selection are all cleared. Trim-mode/duration/export preferences are
  /// left as-is. Used by [applyDailyAutoClear]; also just a plain manual
  /// reset if called directly.
  Future<void> clearContent() => _guarded(() async {
    for (final segment in _segments) {
      if (await segment.file.exists()) {
        await segment.file.delete();
      }
    }
    _segments = [];
    for (final overlay in _textOverlays) {
      final path = overlay.renderedImagePath;
      if (path != null) {
        final file = File(path);
        if (await file.exists()) await file.delete();
      }
    }
    _textOverlays = [];
    _bgmFile = null;
    _bgmTitle = null;
    _bgmStartSeconds = 0;
    _bgmEndSeconds = null;
    await _persistManifest();
    await _persistTextOverlays();
    await _persistSettings();
    await _recompose();
  }, 'まとめ動画のリセットに失敗しました');

  /// 簡易編集's "starts fresh after a day" policy: if this reel has clips
  /// and the oldest of them was added more than 24 hours ago, clears it —
  /// unless [isPremium] is true and the user has turned that off via
  /// [setAutoClearEnabled]. Meant to be called once per app launch, after
  /// this reel and the subscription state have both finished loading (see
  /// main.dart). A no-op for an already-empty reel.
  Future<void> applyDailyAutoClear({required bool isPremium}) async {
    if (isPremium && !_autoClearEnabled) return;
    if (_segments.isEmpty) return;
    final oldest = _segments
        .map((s) => s.createdAt)
        .reduce((a, b) => a.isBefore(b) ? a : b);
    if (DateTime.now().difference(oldest) < _autoClearAfter) return;
    await clearContent();
  }

  /// Adds a new caption or updates an existing one (matched by id).
  /// [overlay] must already have [TextOverlay.renderedImagePath] set to a
  /// PNG snapshot rendered by the editor.
  Future<void> upsertTextOverlay(TextOverlay overlay) => _guarded(() async {
    final index = _textOverlays.indexWhere((o) => o.id == overlay.id);
    _textOverlays = [
      if (index < 0)
        ..._textOverlays
      else ...[
        ..._textOverlays.sublist(0, index),
        ..._textOverlays.sublist(index + 1),
      ],
      overlay,
    ];
    await _persistTextOverlays();
    await _recompose();
  }, 'テキストの保存に失敗しました');

  Future<void> removeTextOverlay(String id) => _guarded(() async {
    final removed = _textOverlays.where((o) => o.id == id).toList();
    _textOverlays = _textOverlays.where((o) => o.id != id).toList();
    for (final overlay in removed) {
      final path = overlay.renderedImagePath;
      if (path != null) {
        final file = File(path);
        if (await file.exists()) await file.delete();
      }
    }
    await _persistTextOverlays();
    await _recompose();
  }, 'テキストの削除に失敗しました');

  Future<void> _persistSettings() async {
    final settings = await _settingsFile();
    await settings.writeAsString(
      jsonEncode({
        'trimMode': _trimMode.name,
        'clipDurationMs': _clipDuration.inMilliseconds,
        'bgmPath': _bgmFile?.path,
        'bgmTitle': _bgmTitle,
        'bgmVolume': _bgmVolume,
        'videoVolume': _videoVolume,
        'bgmStartSeconds': _bgmStartSeconds,
        'bgmEndSeconds': _bgmEndSeconds,
        'exportResolution': _exportResolution.name,
        'exportFps': _exportFps,
        'includeOpening': _includeOpening,
        'autoClearEnabled': _autoClearEnabled,
      }),
    );
  }

  Future<void> _persistManifest() async {
    final manifest = await _manifestFile();
    final raw = jsonEncode(_segments.map((s) => s.toJson()).toList());
    await manifest.writeAsString(raw);
  }

  Future<void> _persistTextOverlays() async {
    final file = await _textOverlaysFile();
    await file.writeAsString(
      jsonEncode(_textOverlays.map((o) => o.toJson()).toList()),
    );
  }

  Future<void> addClip(File sourceClip) => _guarded(() async {
    final segmentsDir = await _segmentsDirectory();
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    final outputFile = File('${segmentsDir.path}/$id.mp4');
    final startOffset = await _computeStartOffset(sourceClip);
    final actualDuration = await _trimClip(
      sourceClip,
      outputFile,
      startOffset,
      _clipDuration,
    );

    _segments = [
      ..._segments,
      HighlightSegment(
        id: id,
        file: outputFile,
        sourcePath: sourceClip.path,
        createdAt: DateTime.now(),
        startOffset: startOffset,
        duration: actualDuration,
        trimModeUsed: _trimMode,
      ),
    ];
    await _persistManifest();
    await _recompose();
  }, 'まとめ動画への追加に失敗しました');

  /// Re-trims a segment using the current [trimMode]. For [ClipTrimMode.random]
  /// this naturally lands somewhere different each time; for
  /// [ClipTrimMode.loudest] it cycles to the next-loudest candidate window
  /// instead of repeating the same (loudest) one. A no-op for
  /// [ClipTrimMode.start]. Reverts to the current global [clipDuration],
  /// discarding any custom length set for this clip via [trimSegment].
  Future<void> redo(int index) => _guarded(() async {
    final segment = _segments[index];
    final source = File(segment.sourcePath);
    if (!await source.exists()) {
      throw Exception('元の動画が見つかりません');
    }
    final nextRedoCount = segment.redoCount + 1;
    final startOffset = await _computeStartOffset(source, rank: nextRedoCount);
    final actualDuration = await _trimClip(
      source,
      segment.file,
      startOffset,
      _clipDuration,
      rotationDegrees: segment.frameRotationDegrees,
      scale: segment.frameScale,
    );

    _segments = [
      for (final s in _segments)
        if (s.id == segment.id)
          s.copyWith(
            redoCount: nextRedoCount,
            startOffset: startOffset,
            duration: actualDuration,
            trimModeUsed: _trimMode,
          )
        else
          s,
    ];
    await _persistManifest();
    await _recompose();
  }, 'クリップの作り直しに失敗しました');

  /// Re-trims a segment's window directly, e.g. by dragging its edges on
  /// the editor timeline. Either argument may be omitted to keep that side
  /// of the current window unchanged. Clamped to the source recording's
  /// actual bounds and a minimum length.
  Future<void> trimSegment(
    int index, {
    Duration? newStartOffset,
    Duration? newDuration,
  }) => _guarded(() async {
    final segment = _segments[index];
    final source = File(segment.sourcePath);
    if (!await source.exists()) {
      throw Exception('元の動画が見つかりません');
    }
    final sourceDuration = await _probeDuration(source);

    var offset = newStartOffset ?? segment.startOffset;
    var duration = newDuration ?? segment.duration;
    if (offset < Duration.zero) offset = Duration.zero;
    if (offset > sourceDuration) offset = sourceDuration;
    const minDuration = Duration(milliseconds: 200);
    if (duration < minDuration) duration = minDuration;
    if (offset + duration > sourceDuration) {
      duration = sourceDuration - offset;
      if (duration < minDuration) {
        offset = sourceDuration - minDuration;
        if (offset < Duration.zero) offset = Duration.zero;
        duration = sourceDuration - offset;
      }
    }

    final actualDuration = await _trimClip(
      source,
      segment.file,
      offset,
      duration,
      rotationDegrees: segment.frameRotationDegrees,
      scale: segment.frameScale,
    );

    _segments = [
      for (final s in _segments)
        if (s.id == segment.id)
          s.copyWith(startOffset: offset, duration: actualDuration)
        else
          s,
    ];
    await _persistManifest();
    await _recompose();
  }, 'クリップのトリミングに失敗しました');

  /// Re-trims a segment's window with new 画角 (framing) values — rotation
  /// in degrees and a center-zoom scale — keeping its current trim window
  /// (start offset/duration) unchanged. Used by the clip framing editor.
  Future<void> setSegmentFraming(
    int index, {
    required double rotationDegrees,
    required double scale,
  }) => _guarded(() async {
    final segment = _segments[index];
    final source = File(segment.sourcePath);
    if (!await source.exists()) {
      throw Exception('元の動画が見つかりません');
    }
    final actualDuration = await _trimClip(
      source,
      segment.file,
      segment.startOffset,
      segment.duration,
      rotationDegrees: rotationDegrees,
      scale: scale,
    );

    _segments = [
      for (final s in _segments)
        if (s.id == segment.id)
          s.copyWith(
            duration: actualDuration,
            frameRotationDegrees: rotationDegrees,
            frameScale: scale,
          )
        else
          s,
    ];
    await _persistManifest();
    await _recompose();
  }, '画角の変更に失敗しました');

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

  /// Sets clip [index]'s own audio volume (0 = silent, 1 = original level,
  /// can go higher), independent of every other clip and of the overall
  /// [videoVolume] multiplier.
  Future<void> setSegmentVolume(int index, double volume) => _guarded(() async {
    final updated = [..._segments];
    updated[index] = updated[index].copyWith(volume: volume);
    _segments = updated;
    await _persistManifest();
    await _recompose();
  }, 'クリップの音量設定に失敗しました');

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
      '-v',
      'error',
      '-show_entries',
      'format=duration',
      '-of',
      'default=noprint_wrappers=1:nokey=1',
      source.path,
    ]);
    final output = (await session.getOutput())?.trim();
    final seconds = double.tryParse(output ?? '') ?? 0;
    if (!seconds.isFinite || seconds <= 0) return Duration.zero;
    return Duration(milliseconds: (seconds * 1000).round());
  }

  /// Cumulative start time of each segment, plus a final entry for the
  /// total duration. `starts[i]` is when segment `i` begins;
  /// `starts[segments.length]` is the total compiled (pre-BGM/text) length.
  /// Exposed publicly so the editor can draw clip-boundary tick marks and
  /// know the total duration for its text-timing timeline.
  List<Duration> segmentStartTimes() {
    final starts = <Duration>[Duration.zero];
    var cursor = Duration.zero;
    for (final segment in _segments) {
      cursor += segment.duration;
      starts.add(cursor);
    }
    return starts;
  }

  Future<Duration> _computeStartOffset(File source, {int rank = 0}) async {
    switch (_trimMode) {
      case ClipTrimMode.start:
        return Duration.zero;
      case ClipTrimMode.random:
        final duration = await _probeDuration(source);
        final maxStartMs =
            duration.inMilliseconds - _clipDuration.inMilliseconds;
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
      '-ss',
      offsetSeconds.toStringAsFixed(2),
      '-t',
      (_clipDuration.inMilliseconds / 1000).toStringAsFixed(2),
      '-i',
      source.path,
      '-af',
      'volumedetect',
      '-f',
      'null',
      '-',
    ]);
    final logs = await session.getAllLogsAsString() ?? '';
    final match = RegExp(
      r'mean_volume:\s*(-?\d+(\.\d+)?)\s*dB',
    ).firstMatch(logs);
    if (match == null) return null;
    return double.tryParse(match.group(1)!);
  }

  /// Trims [source] starting at [startOffset] for [duration] into [output],
  /// returning the trimmed file's actual duration (which can be shorter than
  /// requested if [startOffset]+[duration] runs past the end of [source]).
  /// [rotationDegrees] and [scale] apply the clip's 画角 (framing) edits —
  /// a straighten/rotate and a center zoom — before fitting into the canvas.
  Future<Duration> _trimClip(
    File source,
    File output,
    Duration startOffset,
    Duration duration, {
    double rotationDegrees = 0,
    double scale = 1,
  }) async {
    final filters = <String>[];
    if (rotationDegrees != 0) {
      final radians = rotationDegrees * pi / 180;
      filters.add(
        'rotate=${radians.toStringAsFixed(6)}:fillcolor=black:ow=iw:oh=ih',
      );
    }
    if (scale != 1) {
      filters.add('scale=iw*$scale:ih*$scale,crop=iw/$scale:ih/$scale');
    }
    filters.add(
      'scale=w=$canvasWidth:h=$canvasHeight:force_original_aspect_ratio=decrease',
    );
    filters.add('pad=$canvasWidth:$canvasHeight:(ow-iw)/2:(oh-ih)/2,setsar=1');

    final session = await FFmpegKit.executeWithArguments([
      '-y',
      '-ss',
      (startOffset.inMilliseconds / 1000).toStringAsFixed(2),
      '-i',
      source.path,
      '-t',
      (duration.inMilliseconds / 1000).toStringAsFixed(2),
      '-vf',
      filters.join(','),
      '-r',
      '30',
      '-c:v',
      'libx264',
      '-preset',
      'veryfast',
      '-c:a',
      'aac',
      '-ar',
      '44100',
      '-ac',
      '2',
      output.path,
    ]);
    final returnCode = await session.getReturnCode();
    if (!ReturnCode.isSuccess(returnCode)) {
      throw Exception('ffmpeg trim failed');
    }
    return _probeDuration(output);
  }

  /// The full duration of a segment's original source recording, used to
  /// clamp how far the editor timeline can extend a clip's trim window.
  Future<Duration> sourceDurationFor(HighlightSegment segment) =>
      _probeDuration(File(segment.sourcePath));

  /// Rebuilds [compiledFile]/[previewFile] from this reel's own current
  /// segments/captions/BGM, even though nothing has logically changed. Used
  /// as a startup migration fixup (see [CompilationLibrary.load]) for
  /// installs from before 簡易編集 and 編集 had separate projects — their
  /// compiled video kept the same on-disk path across that split, so
  /// without this it could otherwise keep serving whatever was last
  /// compiled back when both tabs still shared one reel. Best-effort: a
  /// failure here is swallowed rather than blocking app startup on it.
  Future<void> forceRecompose() async {
    try {
      await _recompose();
    } catch (_) {
      // Leave whatever was already compiled in place.
    }
    notifyListeners();
  }

  /// Trims segment [index]'s current window from its source with no framing
  /// applied, as a clean baseline for the framing editor's live preview —
  /// so a Flutter-side Transform can show the chosen rotation/scale
  /// accurately regardless of whatever framing was previously baked in.
  Future<File> extractUnframedPreview(int index) async {
    final segment = _segments[index];
    final source = File(segment.sourcePath);
    final highlightsDir = await _highlightsDirectory();
    final output = File('${highlightsDir.path}/framing_preview.mp4');
    await _trimClip(source, output, segment.startOffset, segment.duration);
    return output;
  }

  /// Builds a one-off copy of [compiledFile] with the "AOK Craft" watermark
  /// burned in at the center and bottom-right, for the 編集 tab's download
  /// flow to use when the downloader isn't premium. Returns null if there's
  /// nothing compiled yet. Not cached — callers just discard the result
  /// after downloading it.
  Future<File?> buildWatermarkedCopy() async {
    final source = _compiledFile;
    if (source == null) return null;

    final highlightsDir = await _highlightsDirectory();
    final watermark = await renderWatermarkPng();

    const cornerMargin = 24;
    final centerX = (canvasWidth - watermark.width) ~/ 2;
    final centerY = (canvasHeight - watermark.height) ~/ 2;
    final cornerX = canvasWidth - watermark.width - cornerMargin;
    final cornerY = canvasHeight - watermark.height - cornerMargin;

    final output = File('${highlightsDir.path}/watermarked.mp4');
    if (await output.exists()) {
      await output.delete();
    }
    final session = await FFmpegKit.executeWithArguments([
      '-y',
      '-i',
      source.path,
      '-i',
      watermark.file.path,
      '-filter_complex',
      '[0:v][1:v]overlay=x=$centerX:y=$centerY[tmp];'
          '[tmp][1:v]overlay=x=$cornerX:y=$cornerY,format=yuv420p[outv]',
      '-map',
      '[outv]',
      '-map',
      '0:a?',
      '-c:v',
      'libx264',
      '-pix_fmt',
      'yuv420p',
      '-preset',
      'veryfast',
      '-c:a',
      'copy',
      output.path,
    ]);
    if (!ReturnCode.isSuccess(await session.getReturnCode())) {
      throw Exception('ffmpeg watermark failed');
    }
    return output;
  }

  Future<void> _recompose() async {
    final output = await _compiledOutputFile();

    if (_segments.isEmpty) {
      if (await output.exists()) {
        await output.delete();
      }
      _compiledFile = null;
      _previewFile = null;
      _revision++;
      return;
    }

    final highlightsDir = await _highlightsDirectory();

    // Clips with a custom volume get an audio-only re-encode pass (video
    // stream just copied through) before concatenation, since the concat
    // demuxer below can only stitch files together as-is — there's no
    // per-segment filter left to apply afterwards once they're joined into
    // one audio stream.
    final concatFiles = <File>[];
    for (final segment in _segments) {
      if (segment.volume == 1) {
        concatFiles.add(segment.file);
        continue;
      }
      final volOutput = File('${highlightsDir.path}/segvol_${segment.id}.mp4');
      if (await volOutput.exists()) {
        await volOutput.delete();
      }
      final volSession = await FFmpegKit.executeWithArguments([
        '-y',
        '-i',
        segment.file.path,
        '-af',
        'volume=${segment.volume}',
        '-c:v',
        'copy',
        '-c:a',
        'aac',
        '-ar',
        '44100',
        '-ac',
        '2',
        volOutput.path,
      ]);
      if (!ReturnCode.isSuccess(await volSession.getReturnCode())) {
        throw Exception('ffmpeg clip volume adjust failed');
      }
      concatFiles.add(volOutput);
    }

    final listFile = File('${highlightsDir.path}/concat_list.txt');
    final buffer = StringBuffer();
    for (final file in concatFiles) {
      final escapedPath = file.path.replaceAll("'", r"'\''");
      buffer.writeln("file '$escapedPath'");
    }
    await listFile.writeAsString(buffer.toString());

    final concatOutput = File('${highlightsDir.path}/concat_raw.mp4');
    if (await concatOutput.exists()) {
      await concatOutput.delete();
    }

    final concatSession = await FFmpegKit.executeWithArguments([
      '-y',
      '-f',
      'concat',
      '-safe',
      '0',
      '-i',
      listFile.path,
      '-c',
      'copy',
      concatOutput.path,
    ]);
    if (!ReturnCode.isSuccess(await concatSession.getReturnCode())) {
      throw Exception('ffmpeg concat failed');
    }

    File current = concatOutput;

    final bgm = _bgmFile;
    final bgmSpanValid =
        _bgmEndSeconds == null || _bgmEndSeconds! - _bgmStartSeconds > 0.05;
    if (bgm != null && bgmSpanValid && await bgm.exists()) {
      // Loops the BGM (so short tracks still fill their placed span), then
      // trims to the span the 編集 tab's timeline placed it at and delays
      // it to start at the right point in the video's own timeline, before
      // mixing with the clips' own audio (each independently volume-scaled).
      final videoTotalSeconds =
          (await _probeDuration(current)).inMilliseconds / 1000;
      final bgmStart = _bgmStartSeconds.clamp(0.0, videoTotalSeconds);
      final bgmEnd = (_bgmEndSeconds ?? videoTotalSeconds).clamp(
        bgmStart,
        videoTotalSeconds,
      );
      final bgmSpan = bgmEnd - bgmStart;
      final bgmStartMs = (bgmStart * 1000).round();

      final bgmOutput = File('${highlightsDir.path}/with_bgm.mp4');
      if (await bgmOutput.exists()) {
        await bgmOutput.delete();
      }
      final muxSession = await FFmpegKit.executeWithArguments([
        '-y',
        '-i',
        current.path,
        '-stream_loop',
        '-1',
        '-i',
        bgm.path,
        '-filter_complex',
        '[0:a]volume=$_videoVolume[a0];'
            '[1:a]volume=$_bgmVolume,atrim=0:${bgmSpan.toStringAsFixed(3)},'
            'adelay=$bgmStartMs|$bgmStartMs[a1];'
            '[a0][a1]amix=inputs=2:duration=first:dropout_transition=0:normalize=0[aout]',
        '-map',
        '0:v:0',
        '-map',
        '[aout]',
        '-c:v',
        'copy',
        '-c:a',
        'aac',
        '-ar',
        '44100',
        '-ac',
        '2',
        '-shortest',
        bgmOutput.path,
      ]);
      if (!ReturnCode.isSuccess(await muxSession.getReturnCode())) {
        throw Exception('ffmpeg bgm mux failed');
      }
      current = bgmOutput;
    } else if (_videoVolume != 1) {
      final volumeOutput = File('${highlightsDir.path}/with_volume.mp4');
      if (await volumeOutput.exists()) {
        await volumeOutput.delete();
      }
      final volumeSession = await FFmpegKit.executeWithArguments([
        '-y',
        '-i',
        current.path,
        '-af',
        'volume=$_videoVolume',
        '-c:v',
        'copy',
        '-c:a',
        'aac',
        '-ar',
        '44100',
        '-ac',
        '2',
        volumeOutput.path,
      ]);
      if (!ReturnCode.isSuccess(await volumeSession.getReturnCode())) {
        throw Exception('ffmpeg volume adjust failed');
      }
      current = volumeOutput;
    }

    // Snapshot the video here — clips + BGM/volume, no captions or opening
    // yet — as the dedicated preview file. The 編集 tab's live preview
    // plays this and renders every caption purely as Flutter widgets
    // instead, so a caption never has to fight for visibility with an
    // already-burned-in copy of itself.
    final previewOutput = File('${highlightsDir.path}/preview.mp4');
    if (await previewOutput.exists()) {
      await previewOutput.delete();
    }
    await current.copy(previewOutput.path);
    _previewFile = previewOutput;

    final renderedOverlays = <TextOverlay>[];
    for (final overlay in _textOverlays) {
      final path = overlay.renderedImagePath;
      if (path != null && await File(path).exists()) {
        renderedOverlays.add(overlay);
      }
    }
    if (renderedOverlays.isNotEmpty) {
      final totalSeconds =
          (await _probeDuration(current)).inMilliseconds / 1000;

      // All captions are composited in one ffmpeg pass — one input per
      // overlay image, chained through a single filter_complex graph —
      // instead of one full video re-encode per caption. With N captions,
      // re-encoding the whole video N times over (each pass re-encoding
      // the previous pass's already-lossy output) made every single edit
      // slower the more captions existed, and the repeated libx264 work
      // was the main source of the app running hot.
      final stepOutput = File('${highlightsDir.path}/text_overlays.mp4');
      if (await stepOutput.exists()) {
        await stepOutput.delete();
      }

      final inputArgs = <String>['-i', current.path];
      final filterStages = <String>[];
      var lastLabel = '0:v';
      for (var i = 0; i < renderedOverlays.length; i++) {
        final overlay = renderedOverlays[i];
        final inputIndex = i + 1;
        inputArgs.addAll([
          '-loop',
          '1',
          '-framerate',
          '30',
          '-t',
          totalSeconds.toStringAsFixed(2),
          '-i',
          File(overlay.renderedImagePath!).path,
        ]);

        final clampedStart = overlay.startSeconds.clamp(0.0, totalSeconds);
        final clampedEnd = overlay.endSeconds.clamp(0.0, totalSeconds);
        final width = overlay.renderedWidth ?? 0;
        final height = overlay.renderedHeight ?? 0;
        final px = (overlay.x * canvasWidth - width / 2).round();
        final py = (overlay.y * canvasHeight - height / 2).round();
        final isLast = i == renderedOverlays.length - 1;
        final outLabel = isLast ? 'outv' : 'tmp$i';

        // The PNG overlay carries an alpha channel, which can leave the
        // filter graph's output in a pixel format (e.g. yuva420p) that
        // encodes "successfully" but that AVFoundation/video_player can't
        // decode as anything but black. Force back to plain yuv420p on the
        // final stage before encoding, rather than relying on ffmpeg's
        // implicit per-container defaults.
        filterStages.add(
          "[$lastLabel][$inputIndex:v]overlay=x=$px:y=$py:enable='between(t\\,"
          '${clampedStart.toStringAsFixed(2)}\\,'
          "${clampedEnd.toStringAsFixed(2)})'"
          "${isLast ? ',format=yuv420p' : ''}[$outLabel]",
        );
        lastLabel = outLabel;
      }

      final session = await FFmpegKit.executeWithArguments([
        '-y',
        ...inputArgs,
        '-filter_complex',
        filterStages.join(';'),
        '-map',
        '[outv]',
        '-map',
        '0:a?',
        '-c:v',
        'libx264',
        '-pix_fmt',
        'yuv420p',
        '-preset',
        'veryfast',
        '-c:a',
        'copy',
        stepOutput.path,
      ]);
      if (!ReturnCode.isSuccess(await session.getReturnCode())) {
        throw Exception('ffmpeg text overlay failed');
      }
      current = stepOutput;
    }

    final opening = await _buildOpeningIfNeeded(highlightsDir);
    if (opening != null) {
      final withOpening = File('${highlightsDir.path}/with_opening.mp4');
      if (await withOpening.exists()) {
        await withOpening.delete();
      }
      final prependSession = await FFmpegKit.executeWithArguments([
        '-y',
        '-i',
        opening.path,
        '-i',
        current.path,
        '-filter_complex',
        '[0:v][0:a][1:v][1:a]concat=n=2:v=1:a=1[outv][outa]',
        '-map',
        '[outv]',
        '-map',
        '[outa]',
        '-c:v',
        'libx264',
        '-preset',
        'veryfast',
        '-c:a',
        'aac',
        '-ar',
        '44100',
        '-ac',
        '2',
        withOpening.path,
      ]);
      if (!ReturnCode.isSuccess(await prependSession.getReturnCode())) {
        throw Exception('ffmpeg opening prepend failed');
      }
      current = withOpening;
    }

    if (_exportResolution == ExportResolution.uhd || _exportFps != 30) {
      final exportOutput = File('${highlightsDir.path}/export_final.mp4');
      if (await exportOutput.exists()) {
        await exportOutput.delete();
      }
      final exportSession = await FFmpegKit.executeWithArguments([
        '-y',
        '-i',
        current.path,
        '-vf',
        'scale=${_exportResolution.width}:${_exportResolution.height}',
        '-r',
        '$_exportFps',
        '-c:v',
        'libx264',
        '-preset',
        'veryfast',
        '-c:a',
        'copy',
        exportOutput.path,
      ]);
      if (!ReturnCode.isSuccess(await exportSession.getReturnCode())) {
        throw Exception('ffmpeg export resolution/fps pass failed');
      }
      current = exportOutput;
    }

    final tempOutput = File('${output.path}.tmp.mp4');
    if (await tempOutput.exists()) {
      await tempOutput.delete();
    }
    await current.copy(tempOutput.path);

    if (await output.exists()) {
      await output.delete();
    }
    await tempOutput.rename(output.path);
    _compiledFile = output;
    _revision++;
  }

  /// Builds an "opening" clip from the middle 1 second of each segment's
  /// *source* recording (not the already-trimmed highlight window), to be
  /// prepended before the main compiled video. Returns null if the opening
  /// is disabled, there aren't enough clips yet, or nothing could be built.
  String _segmentsFingerprint() => _segments
      .map(
        (s) =>
            '${s.id}:${s.startOffset.inMilliseconds}:'
            '${s.duration.inMilliseconds}:${s.frameRotationDegrees}:'
            '${s.frameScale}',
      )
      .join('|');

  Future<File?> _buildOpeningIfNeeded(Directory highlightsDir) async {
    if (!_includeOpening || _segments.length < minClipsForOpening) {
      _cachedOpeningFile = null;
      _cachedOpeningFingerprint = null;
      return null;
    }
    final fingerprint = _segmentsFingerprint();
    final cached = _cachedOpeningFile;
    if (_cachedOpeningFingerprint == fingerprint &&
        cached != null &&
        await cached.exists()) {
      return cached;
    }
    const pieceDuration = Duration(seconds: 1);
    final pieceFiles = <File>[];
    for (var i = 0; i < _segments.length; i++) {
      final segment = _segments[i];
      final source = File(segment.sourcePath);
      if (!await source.exists()) continue;
      final sourceDuration = await _probeDuration(source);
      if (sourceDuration <= Duration.zero) continue;

      var mid = Duration(
        milliseconds:
            (sourceDuration.inMilliseconds - pieceDuration.inMilliseconds) ~/ 2,
      );
      if (mid < Duration.zero) mid = Duration.zero;
      var actualPieceDuration = pieceDuration;
      if (mid + actualPieceDuration > sourceDuration) {
        actualPieceDuration = sourceDuration - mid;
      }
      if (actualPieceDuration <= Duration.zero) continue;

      final pieceFile = File('${highlightsDir.path}/opening_piece_$i.mp4');
      await _trimClip(
        source,
        pieceFile,
        mid,
        actualPieceDuration,
        rotationDegrees: segment.frameRotationDegrees,
        scale: segment.frameScale,
      );
      pieceFiles.add(pieceFile);
    }
    if (pieceFiles.isEmpty) return null;

    final openingListFile = File('${highlightsDir.path}/opening_list.txt');
    final buffer = StringBuffer();
    for (final f in pieceFiles) {
      final escapedPath = f.path.replaceAll("'", r"'\''");
      buffer.writeln("file '$escapedPath'");
    }
    await openingListFile.writeAsString(buffer.toString());

    final openingOutput = File('${highlightsDir.path}/opening.mp4');
    if (await openingOutput.exists()) {
      await openingOutput.delete();
    }
    final session = await FFmpegKit.executeWithArguments([
      '-y',
      '-f',
      'concat',
      '-safe',
      '0',
      '-i',
      openingListFile.path,
      '-c',
      'copy',
      openingOutput.path,
    ]);
    if (!ReturnCode.isSuccess(await session.getReturnCode())) {
      throw Exception('ffmpeg opening concat failed');
    }
    _cachedOpeningFile = openingOutput;
    _cachedOpeningFingerprint = fingerprint;
    return openingOutput;
  }

  /// Deep-copies this reel's full state (segments, text overlays, trim
  /// settings, BGM reference) into [target], which must be a distinct,
  /// freshly-constructed reel. Segment and overlay-image files are copied
  /// into [target]'s own directory rather than shared, so the two reels can
  /// be edited independently afterwards. The BGM file itself lives in
  /// [SoundLibrary]'s directory and is safe to reference from both.
  Future<void> cloneInto(HighlightReel target) => target._guarded(() async {
    final targetSegmentsDir = await target._segmentsDirectory();
    final newSegments = <HighlightSegment>[];
    for (final segment in _segments) {
      final newFile = File('${targetSegmentsDir.path}/${segment.id}.mp4');
      if (await segment.file.exists()) {
        await segment.file.copy(newFile.path);
      }
      newSegments.add(
        HighlightSegment(
          id: segment.id,
          file: newFile,
          sourcePath: segment.sourcePath,
          createdAt: segment.createdAt,
          startOffset: segment.startOffset,
          duration: segment.duration,
          redoCount: segment.redoCount,
          frameRotationDegrees: segment.frameRotationDegrees,
          frameScale: segment.frameScale,
          volume: segment.volume,
          trimModeUsed: segment.trimModeUsed,
        ),
      );
    }

    final targetTextDir = await target.textOverlayImagesDirectory();
    final newOverlays = <TextOverlay>[];
    for (final overlay in _textOverlays) {
      final sourcePath = overlay.renderedImagePath;
      final sourceImage = sourcePath == null ? null : File(sourcePath);
      if (sourceImage == null || !await sourceImage.exists()) continue;
      final newImage = File('${targetTextDir.path}/${overlay.id}.png');
      await sourceImage.copy(newImage.path);
      newOverlays.add(
        TextOverlay(
          id: overlay.id,
          text: overlay.text,
          fontId: overlay.fontId,
          fontSize: overlay.fontSize,
          color: overlay.color,
          x: overlay.x,
          y: overlay.y,
          rotationDegrees: overlay.rotationDegrees,
          startSeconds: overlay.startSeconds,
          endSeconds: overlay.endSeconds,
          renderedImagePath: newImage.path,
          renderedWidth: overlay.renderedWidth,
          renderedHeight: overlay.renderedHeight,
        ),
      );
    }

    target._segments = newSegments;
    target._textOverlays = newOverlays;
    target._trimMode = _trimMode;
    target._clipDuration = _clipDuration;
    target._bgmFile = _bgmFile;
    target._bgmTitle = _bgmTitle;
    target._bgmVolume = _bgmVolume;
    target._videoVolume = _videoVolume;
    target._bgmStartSeconds = _bgmStartSeconds;
    target._bgmEndSeconds = _bgmEndSeconds;
    target._exportResolution = _exportResolution;
    target._exportFps = _exportFps;
    target._includeOpening = _includeOpening;
    target._autoClearEnabled = _autoClearEnabled;

    await target._persistManifest();
    await target._persistSettings();
    await target._persistTextOverlays();
    await target._recompose();
  }, 'まとめ動画の保存に失敗しました');

  /// Deletes this reel's entire storage directory. Only meaningful for
  /// non-`'current'` (saved) reels.
  Future<void> deleteStorage() async {
    final dir = await _highlightsDirectory();
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }
}
