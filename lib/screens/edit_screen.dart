import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:video_player/video_player.dart';

import '../models/app_font.dart';
import '../models/compilation_library.dart';
import '../models/download_quota.dart';
import '../models/highlight_reel.dart';
import '../models/sound_library.dart';
import '../models/subscription_service.dart';
import '../models/text_overlay.dart';
import '../models/video_library.dart';
import '../widgets/clip_management_section.dart';
import '../widgets/compiled_preview_section.dart';
import 'sound_library_screen.dart';

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
  List<TextOverlay> _draftOverlays = [];
  final Map<String, GlobalKey> _overlayKeys = {};
  double _previewWidth = 1;

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
    _previewController?.dispose();
    super.dispose();
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
    for (final overlay in _draftOverlays) {
      _overlayKeys.putIfAbsent(overlay.id, () => GlobalKey());
    }
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
      _overlayKeys.clear();
    });
    _syncFromReel();
    await _loadPreview();
  }

  Future<void> _loadPreview() async {
    final file = _activeReel.compiledFile;
    final oldController = _previewController;
    _previewController = null;
    _previewRevision = _activeReel.revision;
    await oldController?.dispose();
    if (file == null) {
      if (mounted) setState(() {});
      return;
    }
    final controller = VideoPlayerController.file(file);
    try {
      await controller.initialize();
      await controller.seekTo(Duration.zero);
      await controller.pause();
    } catch (_) {
      return;
    }
    if (!mounted) {
      await controller.dispose();
      return;
    }
    setState(() => _previewController = controller);
  }

  Future<void> _renderAndSave(TextOverlay overlay) async {
    final key = _overlayKeys[overlay.id];
    final boundary =
        key?.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return;
    final pixelRatio = HighlightReel.canvasWidth / _previewWidth;
    final image = await boundary.toImage(pixelRatio: pixelRatio);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) return;
    final dir = await _activeReel.textOverlayImagesDirectory();
    final file = File('${dir.path}/${overlay.id}.png');
    await file.writeAsBytes(byteData.buffer.asUint8List());
    final updated = overlay.copyWith(
      renderedImagePath: file.path,
      renderedWidth: image.width,
      renderedHeight: image.height,
    );
    await _activeReel.upsertTextOverlay(updated);
  }

  Future<void> _handleFormResult(TextOverlay overlay, {required bool isNew}) async {
    setState(() {
      if (isNew) {
        _overlayKeys[overlay.id] = GlobalKey();
        _draftOverlays = [..._draftOverlays, overlay];
      } else {
        _draftOverlays = [
          for (final o in _draftOverlays)
            if (o.id == overlay.id) overlay else o,
        ];
      }
    });
    await WidgetsBinding.instance.endOfFrame;
    await _renderAndSave(overlay);
  }

  Future<void> _addText() async {
    final segments = _activeReel.segments;
    if (segments.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('先にクリップを追加してください')));
      return;
    }
    final result = await showModalBottomSheet<TextOverlay>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _TextOverlayFormSheet(
        initial: TextOverlay(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          text: '',
          fontId: AppFont.all.first.id,
          fontSize: 64,
          color: Colors.white,
          x: 0.5,
          y: 0.5,
          rotationDegrees: 0,
          startClipIndex: 0,
          endClipIndex: segments.length - 1,
        ),
        maxClipIndex: segments.length - 1,
      ),
    );
    if (result == null || result.text.trim().isEmpty) return;
    await _handleFormResult(result, isNew: true);
  }

  Future<void> _editText(TextOverlay overlay) async {
    final maxClipIndex = _activeReel.segments.length - 1;
    if (maxClipIndex < 0) return;
    final result = await showModalBottomSheet<TextOverlay>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _TextOverlayFormSheet(
        initial: overlay,
        maxClipIndex: maxClipIndex,
      ),
    );
    if (result == null) return;
    await _handleFormResult(result, isNew: false);
  }

  Future<void> _deleteText(TextOverlay overlay) async {
    setState(() {
      _draftOverlays = _draftOverlays.where((o) => o.id != overlay.id).toList();
      _overlayKeys.remove(overlay.id);
    });
    await _activeReel.removeTextOverlay(overlay.id);
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
    await _renderAndSave(overlay);
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

  @override
  Widget build(BuildContext context) {
    final reel = _activeReel;
    return Scaffold(
      appBar: AppBar(
        title: const Text('編集'),
        actions: [
          IconButton(
            icon: const Icon(Icons.save_alt),
            tooltip: 'まとめ動画として保存',
            onPressed: _handleSaveAsNew,
          ),
        ],
      ),
      body: Stack(
        children: [
          ListView(
            children: [
              _buildCompilationPicker(),
              const Divider(height: 1),
              if (reel.errorMessage != null)
                Container(
                  width: double.infinity,
                  color: Colors.red.shade100,
                  padding: const EdgeInsets.all(12),
                  child: Text(reel.errorMessage!),
                ),
              if (reel.isProcessing)
                const LinearProgressIndicator(minHeight: 3),
              _buildPreview(),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: CompiledPreviewSection(
                  reel: reel,
                  subscriptionService: widget.subscriptionService,
                  downloadQuota: widget.downloadQuota,
                ),
              ),
              const Divider(height: 1),
              ClipManagementSection(
                reel: reel,
                subscriptionService: widget.subscriptionService,
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('BGM', style: Theme.of(context).textTheme.labelLarge),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: _handlePickBgm,
                      icon: const Icon(Icons.music_note),
                      label: Text(reel.bgmTitle ?? 'BGMなし'),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'テキスト',
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                        FilledButton.tonalIcon(
                          onPressed: _addText,
                          icon: const Icon(Icons.add),
                          label: const Text('追加'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'プレビュー上でドラッグして位置調整、ピンチで拡大縮小、2本指で回転できます。',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              if (_draftOverlays.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Text('まだテキストがありません'),
                )
              else
                for (final overlay in _draftOverlays)
                  ListTile(
                    leading: Icon(Icons.text_fields, color: overlay.color),
                    title: Text(overlay.text),
                    subtitle: Text(
                      '${AppFont.byId(overlay.fontId).displayName} / '
                      '${overlay.startClipIndex + 1}〜${overlay.endClipIndex + 1}番目',
                    ),
                    onTap: () => _editText(overlay),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => _deleteText(overlay),
                    ),
                  ),
              const SizedBox(height: 24),
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
    );
  }

  Widget _buildCompilationPicker() {
    final library = widget.compilationLibrary;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('編集するまとめ動画', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          SingleChildScrollView(
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
                    onDeleted: () => _handleDeleteSaved(entry.id, entry.title),
                  ),
                ],
              ],
            ),
          ),
          if (_selectedId != 'current') ...[
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () {
                  final entry = library.saved
                      .where((c) => c.id == _selectedId)
                      .firstOrNull;
                  if (entry == null) return;
                  _handleRename(entry.id, entry.title);
                },
                icon: const Icon(Icons.edit, size: 16),
                label: const Text('タイトルを変更'),
              ),
            ),
          ],
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
                  const Center(
                    child: Text(
                      'まとめ動画がありません',
                      style: TextStyle(color: Colors.white70),
                    ),
                  ),
                for (final overlay in _draftOverlays)
                  _buildOverlayWidget(overlay, _previewWidth, previewHeight),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildOverlayWidget(
    TextOverlay overlay,
    double previewWidth,
    double previewHeight,
  ) {
    final key = _overlayKeys[overlay.id] ??= GlobalKey();
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
        child: RepaintBoundary(
          key: key,
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
      ),
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

class _TextOverlayFormSheet extends StatefulWidget {
  const _TextOverlayFormSheet({required this.initial, required this.maxClipIndex});

  final TextOverlay initial;
  final int maxClipIndex;

  @override
  State<_TextOverlayFormSheet> createState() => _TextOverlayFormSheetState();
}

class _TextOverlayFormSheetState extends State<_TextOverlayFormSheet> {
  late final TextEditingController _controller;
  late String _fontId;
  late double _fontSize;
  late Color _color;
  late int _startClip;
  late int _endClip;

  static const _presetColors = [
    Colors.white,
    Colors.black,
    Colors.red,
    Colors.orange,
    Colors.yellow,
    Colors.green,
    Colors.blue,
    Colors.purple,
    Colors.pink,
    Colors.cyan,
    Colors.brown,
    Colors.grey,
  ];

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initial.text);
    _fontId = widget.initial.fontId;
    _fontSize = widget.initial.fontSize;
    _color = widget.initial.color;
    _startClip = widget.initial.startClipIndex.clamp(0, widget.maxClipIndex);
    _endClip = widget.initial.endClipIndex.clamp(0, widget.maxClipIndex);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _pickCustomColor() async {
    var picked = _color;
    final result = await showDialog<Color>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('色を選択'),
        content: SingleChildScrollView(
          child: ColorPicker(
            pickerColor: _color,
            onColorChanged: (c) => picked = c,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(picked),
            child: const Text('決定'),
          ),
        ],
      ),
    );
    if (result != null) setState(() => _color = result);
  }

  void _save() {
    final text = _controller.text.trim();
    if (text.isEmpty) {
      Navigator.of(context).pop();
      return;
    }
    final start = _startClip <= _endClip ? _startClip : _endClip;
    final end = _endClip >= _startClip ? _endClip : _startClip;
    Navigator.of(context).pop(
      widget.initial.copyWith(
        text: text,
        fontId: _fontId,
        fontSize: _fontSize,
        color: _color,
        startClipIndex: start,
        endClipIndex: end,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _controller,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'テキスト'),
              maxLines: 2,
            ),
            const SizedBox(height: 16),
            Text('フォント', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            SizedBox(
              height: 72,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: AppFont.all.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final font = AppFont.all[index];
                  final selected = font.id == _fontId;
                  return GestureDetector(
                    onTap: () => setState(() => _fontId = font.id),
                    child: Container(
                      width: 72,
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      decoration: BoxDecoration(
                        color: selected
                            ? Theme.of(context).colorScheme.primaryContainer
                            : Theme.of(
                                context,
                              ).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'あ',
                            style: TextStyle(
                              fontFamily: font.familyName,
                              fontSize: 24,
                            ),
                          ),
                          Text(
                            font.displayName,
                            style: const TextStyle(fontSize: 9),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            Text('サイズ', style: Theme.of(context).textTheme.labelLarge),
            Slider(
              value: _fontSize,
              min: 16,
              max: 200,
              onChanged: (v) => setState(() => _fontSize = v),
            ),
            const SizedBox(height: 8),
            Text('色', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final c in _presetColors)
                  GestureDetector(
                    onTap: () => setState(() => _color = c),
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: c,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: _color.toARGB32() == c.toARGB32()
                              ? Theme.of(context).colorScheme.primary
                              : Colors.grey,
                          width: _color.toARGB32() == c.toARGB32() ? 3 : 1,
                        ),
                      ),
                    ),
                  ),
                GestureDetector(
                  onTap: _pickCustomColor,
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: SweepGradient(
                        colors: [
                          Colors.red,
                          Colors.yellow,
                          Colors.green,
                          Colors.blue,
                          Colors.purple,
                          Colors.red,
                        ],
                      ),
                    ),
                    child: const Icon(
                      Icons.colorize,
                      size: 16,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text('表示するクリップ範囲', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    initialValue: _startClip,
                    decoration: const InputDecoration(labelText: '開始'),
                    items: [
                      for (var i = 0; i <= widget.maxClipIndex; i++)
                        DropdownMenuItem(value: i, child: Text('${i + 1}番目')),
                    ],
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() {
                        _startClip = v;
                        if (_endClip < _startClip) _endClip = _startClip;
                      });
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<int>(
                    initialValue: _endClip,
                    decoration: const InputDecoration(labelText: '終了'),
                    items: [
                      for (var i = 0; i <= widget.maxClipIndex; i++)
                        DropdownMenuItem(value: i, child: Text('${i + 1}番目')),
                    ],
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() {
                        _endClip = v;
                        if (_startClip > _endClip) _startClip = _endClip;
                      });
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('キャンセル'),
                ),
                const SizedBox(width: 8),
                FilledButton(onPressed: _save, child: const Text('保存')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
