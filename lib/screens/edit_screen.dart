import 'dart:math';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../models/app_font.dart';
import '../models/compilation_library.dart';
import '../models/download_quota.dart';
import '../models/highlight_reel.dart';
import '../models/sound_library.dart';
import '../models/subscription_service.dart';
import '../models/text_overlay.dart';
import '../models/video_library.dart';
import '../utils/download_video.dart';
import '../utils/text_overlay_renderer.dart';
import '../widgets/date_template_sheet.dart';
import '../widgets/text_overlay_form_sheet.dart';
import '../widgets/video_editor_timeline.dart';
import 'sound_library_screen.dart';

/// The Adobe Premiere-style advanced editor: video preview + multi-track
/// timeline, no scrolling. Clip trim-mode/duration/basic reorder and simple
/// text adding live in the まとめ tab (簡易編集) instead — this screen is
/// purely the rich, direct-manipulation editing surface for whichever
/// compilation is selected.
class EditScreen extends StatefulWidget {
  const EditScreen({
    super.key,
    required this.compilationLibrary,
    required this.soundLibrary,
    required this.videoLibrary,
    required this.subscriptionService,
    required this.downloadQuota,
  });

  final CompilationLibrary compilationLibrary;
  final SoundLibrary soundLibrary;
  final VideoLibrary videoLibrary;
  final SubscriptionService subscriptionService;
  final DownloadQuota downloadQuota;

  @override
  State<EditScreen> createState() => _EditScreenState();
}

class _EditScreenState extends State<EditScreen> {
  String _selectedId = 'current';
  late HighlightReel _activeReel;
  bool _loadingSelection = false;

  VideoPlayerController? _previewController;
  int _previewRevision = -1;
  String? _previewError;
  bool _isPreviewPlaying = false;
  bool _isDownloading = false;
  List<TextOverlay> _draftOverlays = [];
  double _previewWidth = 1;

  /// Id of the caption selected via the timeline (first tap) — shown as a
  /// draggable/resizable widget in the preview. Every other caption is
  /// already burned into the compiled video itself, so only the selected
  /// one is rendered here to avoid showing it twice.
  String? _selectedCaptionId;

  String? _activeOverlayId;
  double _gestureStartFontSize = 0;
  double _gestureStartRotation = 0;
  double _liveX = 0;
  double _liveY = 0;

  @override
  void initState() {
    super.initState();
    _activeReel = widget.compilationLibrary.current;
    widget.compilationLibrary.addListener(_onLibraryChanged);
    _activeReel.addListener(_onReelChanged);
    _syncFromReel();
    _loadPreview();
  }

  @override
  void dispose() {
    widget.compilationLibrary.removeListener(_onLibraryChanged);
    _activeReel.removeListener(_onReelChanged);
    _previewController?.removeListener(_onPreviewControllerUpdate);
    _previewController?.dispose();
    super.dispose();
  }

  void _onPreviewControllerUpdate() {
    final controller = _previewController;
    if (controller == null || !mounted) return;
    final playing = controller.value.isPlaying;
    if (playing != _isPreviewPlaying) {
      setState(() => _isPreviewPlaying = playing);
    }
    if (!playing &&
        controller.value.duration > Duration.zero &&
        controller.value.position >= controller.value.duration) {
      controller.seekTo(Duration.zero);
    }
  }

  Future<void> _togglePlayback() async {
    final controller = _previewController;
    if (controller == null || !controller.value.isInitialized) return;
    if (controller.value.isPlaying) {
      await controller.pause();
    } else {
      await controller.play();
    }
  }

  void _onLibraryChanged() {
    if (mounted) setState(() {});
  }

  void _onReelChanged() {
    if (!mounted) return;
    _syncFromReel();
    if (_activeReel.revision != _previewRevision) {
      _loadPreview();
    }
    setState(() {});
  }

  void _syncFromReel() {
    _draftOverlays = _activeReel.textOverlays;
  }

  Future<void> _selectCompilation(String id) async {
    if (id == _selectedId || _loadingSelection) return;
    setState(() {
      _selectedId = id;
      _loadingSelection = true;
    });
    final reel = await widget.compilationLibrary.reelFor(id);
    if (!mounted) return;
    _activeReel.removeListener(_onReelChanged);
    reel.addListener(_onReelChanged);
    setState(() {
      _activeReel = reel;
      _loadingSelection = false;
    });
    _syncFromReel();
    await _loadPreview();
  }

  Future<void> _loadPreview() async {
    final file = _activeReel.compiledFile;
    final oldController = _previewController;
    oldController?.removeListener(_onPreviewControllerUpdate);
    _previewController = null;
    _previewError = null;
    _isPreviewPlaying = false;
    _previewRevision = _activeReel.revision;
    await oldController?.dispose();

    if (file == null) {
      if (mounted) setState(() {});
      return;
    }
    final controller = VideoPlayerController.file(file);
    try {
      await controller.initialize();
      await controller.pause();
    } catch (e) {
      if (mounted) setState(() => _previewError = 'プレビューを読み込めませんでした: $e');
      return;
    }
    if (!mounted) {
      await controller.dispose();
      return;
    }
    controller.addListener(_onPreviewControllerUpdate);
    setState(() => _previewController = controller);
  }

  Future<void> _handleFormResult(TextOverlay overlay) async {
    final rendered = await renderTextOverlay(overlay, _activeReel);
    await _activeReel.upsertTextOverlay(rendered);
  }

  /// Entry point for the timeline's "+" button — lets the user choose
  /// between typing a free-text comment or building one from the active
  /// clip's recorded date/time (テンプレート).
  Future<void> _handleAddTextPressed() async {
    if (_activeReel.segments.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('先にクリップを追加してください')));
      return;
    }
    final choice = await showModalBottomSheet<_AddTextChoice>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.text_fields),
              title: const Text('コメント'),
              subtitle: const Text('自由に文字を入力します'),
              onTap: () => Navigator.of(context).pop(_AddTextChoice.comment),
            ),
            ListTile(
              leading: const Icon(Icons.event_note),
              title: const Text('テンプレート'),
              subtitle: const Text('撮影した日時を表示します'),
              onTap: () => Navigator.of(context).pop(_AddTextChoice.template),
            ),
          ],
        ),
      ),
    );
    if (choice == _AddTextChoice.comment) {
      await _addText();
    } else if (choice == _AddTextChoice.template) {
      await _addTemplateText();
    }
  }

  /// The clip whose time range currently covers the preview's playhead —
  /// used to pick which clip's recorded date the テンプレート text uses,
  /// and to scope the new caption to just that clip by default.
  int _activeClipIndexAt(Duration position, List<Duration> starts) {
    final seconds = position.inMilliseconds / 1000;
    for (var i = 0; i < _activeReel.segments.length; i++) {
      final start = starts[i].inMilliseconds / 1000;
      final end = starts[i + 1].inMilliseconds / 1000;
      if (seconds >= start && seconds < end) return i;
    }
    return _activeReel.segments.length - 1;
  }

  Future<void> _addTemplateText() async {
    final segments = _activeReel.segments;
    if (segments.isEmpty) return;
    final starts = _activeReel.segmentStartTimes();
    final position = _previewController?.value.position ?? Duration.zero;
    final index = _activeClipIndexAt(position, starts);
    final segment = segments[index];
    final clipStart = starts[index].inMilliseconds / 1000;
    final clipEnd = starts[index + 1].inMilliseconds / 1000;

    final text = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (context) => DateTemplateSheet(dateTime: segment.createdAt),
    );
    if (text == null || text.trim().isEmpty) return;

    final overlay = TextOverlay(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      text: text,
      fontId: AppFont.all.first.id,
      fontSize: 64,
      color: Colors.white,
      x: 0.5,
      y: 0.5,
      rotationDegrees: 0,
      startSeconds: clipStart,
      endSeconds: clipEnd,
    );
    await _handleFormResult(overlay);
    setState(() => _selectedCaptionId = overlay.id);
  }

  Future<void> _addText() async {
    final segments = _activeReel.segments;
    if (segments.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('先にクリップを追加してください')));
      return;
    }
    final starts = _activeReel.segmentStartTimes();
    final totalSeconds = starts.last.inMilliseconds / 1000;
    final result = await showModalBottomSheet<TextOverlay>(
      context: context,
      isScrollControlled: true,
      builder: (context) => TextOverlayFormSheet(
        initial: TextOverlay(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          text: '',
          fontId: AppFont.all.first.id,
          fontSize: 64,
          color: Colors.white,
          x: 0.5,
          y: 0.5,
          rotationDegrees: 0,
          startSeconds: 0,
          endSeconds: totalSeconds,
        ),
        totalSeconds: totalSeconds,
        clipBoundarySeconds: [
          for (final s in starts) s.inMilliseconds / 1000,
        ],
      ),
    );
    if (result == null || result.text.trim().isEmpty) return;
    await _handleFormResult(result);
    setState(() => _selectedCaptionId = result.id);
  }

  Future<void> _editText(TextOverlay overlay) async {
    if (_activeReel.segments.isEmpty) return;
    final starts = _activeReel.segmentStartTimes();
    final totalSeconds = starts.last.inMilliseconds / 1000;
    final result = await showModalBottomSheet<TextOverlay>(
      context: context,
      isScrollControlled: true,
      builder: (context) => TextOverlayFormSheet(
        initial: overlay,
        totalSeconds: totalSeconds,
        clipBoundarySeconds: [
          for (final s in starts) s.inMilliseconds / 1000,
        ],
        onDelete: () {
          _activeReel.removeTextOverlay(overlay.id);
          if (_selectedCaptionId == overlay.id) {
            setState(() => _selectedCaptionId = null);
          }
        },
      ),
    );
    if (result == null) return;
    await _handleFormResult(result);
  }

  void _handleSelectCaption(String id) {
    setState(() => _selectedCaptionId = id);
  }

  void _beginGesture(TextOverlay overlay) {
    _activeOverlayId = overlay.id;
    _gestureStartFontSize = overlay.fontSize;
    _gestureStartRotation = overlay.rotationDegrees;
    _liveX = overlay.x;
    _liveY = overlay.y;
  }

  void _updateGesture(ScaleUpdateDetails details) {
    final id = _activeOverlayId;
    if (id == null) return;
    _liveX = (_liveX + details.focalPointDelta.dx / _previewWidth).clamp(
      0.0,
      1.0,
    );
    // previewHeight = previewWidth * (canvasHeight / canvasWidth), so the
    // normalized delta is dy / previewHeight, i.e. dy / previewWidth scaled
    // by (canvasWidth / canvasHeight) — not its reciprocal.
    _liveY = (_liveY +
            details.focalPointDelta.dy /
                _previewWidth *
                (HighlightReel.canvasWidth / HighlightReel.canvasHeight))
        .clamp(0.0, 1.0);
    final newFontSize = (_gestureStartFontSize * details.scale).clamp(
      12.0,
      400.0,
    );
    final newRotation =
        _gestureStartRotation + details.rotation * 180 / pi;

    setState(() {
      _draftOverlays = [
        for (final o in _draftOverlays)
          if (o.id == id)
            o.copyWith(
              x: _liveX,
              y: _liveY,
              fontSize: newFontSize,
              rotationDegrees: newRotation,
            )
          else
            o,
      ];
    });
  }

  Future<void> _endGesture() async {
    final id = _activeOverlayId;
    _activeOverlayId = null;
    if (id == null) return;
    final overlay = _draftOverlays.where((o) => o.id == id).firstOrNull;
    if (overlay == null) return;
    await _handleFormResult(overlay);
  }

  Future<void> _handlePickBgm() async {
    final result = await Navigator.of(context).push<SoundSelection>(
      MaterialPageRoute(
        builder: (_) => SoundLibraryScreen(
          soundLibrary: widget.soundLibrary,
          videoLibrary: widget.videoLibrary,
        ),
      ),
    );
    if (result == null) return;
    await _activeReel.setBgm(result.sound);
  }

  Future<void> _handleDownload() async {
    final file = _activeReel.compiledFile;
    if (file == null) return;
    setState(() => _isDownloading = true);
    await downloadCompiledVideo(
      context: context,
      file: file,
      subscriptionService: widget.subscriptionService,
      downloadQuota: widget.downloadQuota,
    );
    if (mounted) setState(() => _isDownloading = false);
  }

  Future<void> _handleSaveAsNew() async {
    final title = await _promptForText(
      dialogTitle: 'まとめ動画を保存',
      fieldLabel: 'タイトル(省略可)',
      confirmLabel: '保存',
    );
    if (title == null) return;
    final entry = await widget.compilationLibrary.saveCurrentAsNew(
      title: title.isEmpty ? null : title,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('「${entry.title}」として保存しました')));
  }

  Future<void> _handleRename(String id, String currentTitle) async {
    final title = await _promptForText(
      dialogTitle: 'タイトルを変更',
      fieldLabel: 'タイトル',
      confirmLabel: '変更',
      initialText: currentTitle,
    );
    if (title == null || title.isEmpty) return;
    await widget.compilationLibrary.renameSaved(id, title);
  }

  Future<String?> _promptForText({
    required String dialogTitle,
    required String fieldLabel,
    required String confirmLabel,
    String initialText = '',
  }) async {
    final controller = TextEditingController(text: initialText);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(dialogTitle),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(labelText: fieldLabel),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  Future<void> _handleDeleteSaved(String id, String title) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('削除しますか?'),
        content: Text('「$title」を削除します。この操作は取り消せません。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('削除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (_selectedId == id) {
      await _selectCompilation('current');
    }
    await widget.compilationLibrary.deleteSaved(id);
  }

  Future<void> _handleCommitClipTrim(
    int index, {
    Duration? newStartOffset,
    Duration? newDuration,
  }) {
    return _activeReel.trimSegment(
      index,
      newStartOffset: newStartOffset,
      newDuration: newDuration,
    );
  }

  /// Timing-only caption edit from the timeline's drag handles.
  Future<void> _handleCommitCaptionTiming(
    TextOverlay overlay,
    double newStart,
    double newEnd,
  ) {
    return _activeReel.upsertTextOverlay(
      overlay.copyWith(startSeconds: newStart, endSeconds: newEnd),
    );
  }

  @override
  Widget build(BuildContext context) {
    final reel = _activeReel;
    return Scaffold(
      appBar: AppBar(
        title: const Text('編集'),
        actions: [
          IconButton(
            icon: const Icon(Icons.music_note),
            tooltip: reel.bgmTitle ?? 'BGMなし',
            onPressed: _handlePickBgm,
          ),
          IconButton(
            icon: _isDownloading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.download),
            tooltip: 'ダウンロード',
            onPressed: reel.compiledFile == null || _isDownloading
                ? null
                : _handleDownload,
          ),
          IconButton(
            icon: const Icon(Icons.save_alt),
            tooltip: 'まとめ動画として保存',
            onPressed: _handleSaveAsNew,
          ),
        ],
      ),
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                _buildCompilationPicker(),
                if (reel.errorMessage != null)
                  Container(
                    width: double.infinity,
                    color: Colors.red.shade100,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    child: Text(
                      reel.errorMessage!,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                if (reel.isProcessing)
                  const LinearProgressIndicator(minHeight: 3),
                Expanded(child: Center(child: _buildPreview())),
                VideoEditorTimeline(
                  reel: reel,
                  segments: reel.segments,
                  overlays: _draftOverlays,
                  previewController: _previewController,
                  onReorderClip: (oldIndex, newIndex) =>
                      reel.reorder(oldIndex, newIndex),
                  onCommitClipTrim: _handleCommitClipTrim,
                  selectedCaptionId: _selectedCaptionId,
                  onSelectCaption: _handleSelectCaption,
                  onTapCaption: _editText,
                  onCommitCaptionTiming: _handleCommitCaptionTiming,
                  onAddText: _handleAddTextPressed,
                ),
                const SizedBox(height: 8),
              ],
            ),
            if (_loadingSelection)
              Positioned.fill(
                child: ColoredBox(
                  color: Colors.black.withValues(alpha: 0.2),
                  child: const Center(child: CircularProgressIndicator()),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCompilationPicker() {
    final library = widget.compilationLibrary;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  ChoiceChip(
                    label: const Text('作成中のまとめ'),
                    selected: _selectedId == 'current',
                    onSelected: (_) => _selectCompilation('current'),
                  ),
                  for (final entry in library.saved) ...[
                    const SizedBox(width: 8),
                    InputChip(
                      label: Text(entry.title),
                      selected: _selectedId == entry.id,
                      onPressed: () => _selectCompilation(entry.id),
                      onDeleted: () =>
                          _handleDeleteSaved(entry.id, entry.title),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (_selectedId != 'current')
            IconButton(
              tooltip: 'タイトルを変更',
              icon: const Icon(Icons.edit, size: 18),
              visualDensity: VisualDensity.compact,
              onPressed: () {
                final entry = library.saved
                    .where((c) => c.id == _selectedId)
                    .firstOrNull;
                if (entry == null) return;
                _handleRename(entry.id, entry.title);
              },
            ),
        ],
      ),
    );
  }

  Widget _buildPreview() {
    return AspectRatio(
      aspectRatio: HighlightReel.canvasWidth / HighlightReel.canvasHeight,
      child: LayoutBuilder(
        builder: (context, constraints) {
          _previewWidth = constraints.maxWidth;
          final previewHeight = constraints.maxHeight;
          final controller = _previewController;
          return Container(
            color: Colors.black,
            child: Stack(
              clipBehavior: Clip.hardEdge,
              children: [
                if (controller != null && controller.value.isInitialized)
                  Positioned.fill(child: VideoPlayer(controller))
                else
                  Center(
                    child: Text(
                      _previewError ?? 'まとめ動画がありません',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ),
                _buildOverlaysLayer(_previewWidth, previewHeight),
                if (controller != null && controller.value.isInitialized)
                  Positioned(
                    right: 12,
                    bottom: 12,
                    child: GestureDetector(
                      onTap: _togglePlayback,
                      child: CircleAvatar(
                        radius: 22,
                        backgroundColor: Colors.black54,
                        child: Icon(
                          _isPreviewPlaying ? Icons.pause : Icons.play_arrow,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// Shows only the timeline-selected caption as a draggable/resizable
  /// widget. Every other caption is already burned into the compiled
  /// video itself, so rendering them here too would just duplicate them
  /// on screen.
  Widget _buildOverlaysLayer(double previewWidth, double previewHeight) {
    final overlay = _draftOverlays
        .where((o) => o.id == _selectedCaptionId)
        .firstOrNull;
    if (overlay == null) return const SizedBox.shrink();
    return _buildOverlayWidget(overlay, previewWidth, previewHeight);
  }

  Widget _buildOverlayWidget(
    TextOverlay overlay,
    double previewWidth,
    double previewHeight,
  ) {
    final font = AppFont.byId(overlay.fontId);
    final previewScale = previewWidth / HighlightReel.canvasWidth;
    final previewFontSize = overlay.fontSize * previewScale;

    final textStyle = TextStyle(
      fontFamily: font.familyName,
      fontSize: previewFontSize,
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
    final boxW = textW * cos(angle).abs() + textH * sin(angle).abs();
    final boxH = textW * sin(angle).abs() + textH * cos(angle).abs();

    final left = overlay.x * previewWidth - boxW / 2;
    final top = overlay.y * previewHeight - boxH / 2;

    return Positioned(
      left: left,
      top: top,
      width: boxW,
      height: boxH,
      child: GestureDetector(
        onScaleStart: (_) => _beginGesture(overlay),
        onScaleUpdate: _updateGesture,
        onScaleEnd: (_) => _endGesture(),
        child: Center(
          child: Transform.rotate(
            angle: angle,
            child: Padding(
              padding: const EdgeInsets.all(padding),
              child: Text(overlay.text, style: textStyle),
            ),
          ),
        ),
      ),
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

enum _AddTextChoice { comment, template }
