import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';

import '../models/app_font.dart';
import '../models/text_overlay.dart';

String formatSeconds(double seconds) {
  final clamped = seconds < 0 ? 0.0 : seconds;
  final minutes = clamped ~/ 60;
  final rest = clamped - minutes * 60;
  return '$minutes:${rest.toStringAsFixed(1).padLeft(4, '0')}';
}

/// Modal bottom sheet for adding/editing a caption's text, font, size,
/// color, and position. Shared by the まとめ tab (簡易編集: add and manage
/// captions from a plain list, timing set via a clip picker) and the 編集
/// タブ (position/rotation are also adjustable directly on its canvas, and
/// timing via either this form's seconds slider or the timeline's drag
/// handles).
///
/// Pops with the updated [TextOverlay] on save, or with no result if
/// cancelled. If [onDelete] is provided, a delete button is shown; tapping
/// it invokes the callback and pops with no result (the caller is
/// responsible for actually deleting).
class TextOverlayFormSheet extends StatefulWidget {
  const TextOverlayFormSheet({
    super.key,
    required this.initial,
    required this.totalSeconds,
    required this.clipBoundarySeconds,
    this.showClipPicker = false,
    this.showSecondsSlider = false,
    this.onDelete,
  });

  final TextOverlay initial;

  /// Total duration of the compiled video (pre-BGM/text), in seconds.
  final double totalSeconds;

  /// Cumulative clip start times (seconds), including 0 and [totalSeconds].
  final List<double> clipBoundarySeconds;

  /// Shows a simple "which clip(s) should this caption appear on" checkbox
  /// picker built from [clipBoundarySeconds] — used by the まとめ tab's
  /// 簡易編集, which has no visual timeline to drag timing on.
  final bool showClipPicker;

  /// Shows a numeric start/end seconds RangeSlider — used by the 編集 tab,
  /// which also has its timeline's drag handles as a second way to adjust
  /// timing.
  final bool showSecondsSlider;

  final VoidCallback? onDelete;

  @override
  State<TextOverlayFormSheet> createState() => _TextOverlayFormSheetState();
}

class _TextOverlayFormSheetState extends State<TextOverlayFormSheet> {
  late final TextEditingController _controller;
  late String _fontId;
  late double _fontSize;
  late Color _color;
  late double _x;
  late double _y;
  late double _rotationDegrees;
  late double _startSeconds;
  late double _endSeconds;
  Set<int> _selectedClipIndices = {};

  static const _fontSizePresets = [
    (label: '小', value: 36.0),
    (label: '中', value: 64.0),
    (label: '大', value: 120.0),
  ];

  static const _positionPresets = [
    (label: '中央', x: 0.5, y: 0.5),
    (label: '中央上', x: 0.5, y: 0.15),
    (label: '中央下', x: 0.5, y: 0.85),
  ];

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
    _x = widget.initial.x;
    _y = widget.initial.y;
    _rotationDegrees = widget.initial.rotationDegrees;
    final maxSeconds = widget.totalSeconds > 0 ? widget.totalSeconds : 0.0;
    _startSeconds = widget.initial.startSeconds.clamp(0.0, maxSeconds);
    _endSeconds = widget.initial.endSeconds.clamp(0.0, maxSeconds);
    if (_startSeconds > _endSeconds) _startSeconds = _endSeconds;
    if (widget.showClipPicker) {
      _selectedClipIndices = _clipIndicesInRange(_startSeconds, _endSeconds);
    }
  }

  /// Which clips (by index into [TextOverlayFormSheet.clipBoundarySeconds])
  /// overlap [start, end] — used to preselect the clip picker's checkboxes
  /// when editing an existing caption. Falls back to every clip if none
  /// overlap (e.g. a zero-length legacy range).
  Set<int> _clipIndicesInRange(double start, double end) {
    final indices = <int>{};
    for (var i = 0; i < widget.clipBoundarySeconds.length - 1; i++) {
      final clipStart = widget.clipBoundarySeconds[i];
      final clipEnd = widget.clipBoundarySeconds[i + 1];
      if (start < clipEnd && end > clipStart) indices.add(i);
    }
    if (indices.isEmpty && widget.clipBoundarySeconds.length > 1) {
      indices.addAll(
        List.generate(widget.clipBoundarySeconds.length - 1, (i) => i),
      );
    }
    return indices;
  }

  /// Toggles clip [index] in the picker, keeping at least one clip
  /// selected, and recomputes the caption's start/end as the contiguous
  /// span from the earliest to the latest selected clip.
  void _toggleClip(int index) {
    setState(() {
      if (_selectedClipIndices.contains(index)) {
        if (_selectedClipIndices.length > 1) {
          _selectedClipIndices.remove(index);
        }
      } else {
        _selectedClipIndices.add(index);
      }
      final minIndex = _selectedClipIndices.reduce((a, b) => a < b ? a : b);
      final maxIndex = _selectedClipIndices.reduce((a, b) => a > b ? a : b);
      _startSeconds = widget.clipBoundarySeconds[minIndex];
      _endSeconds = widget.clipBoundarySeconds[maxIndex + 1];
    });
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
    final start = _startSeconds <= _endSeconds ? _startSeconds : _endSeconds;
    final end = _endSeconds >= _startSeconds ? _endSeconds : _startSeconds;
    Navigator.of(context).pop(
      widget.initial.copyWith(
        text: text,
        fontId: _fontId,
        fontSize: _fontSize,
        color: _color,
        x: _x,
        y: _y,
        rotationDegrees: _rotationDegrees,
        startSeconds: start,
        endSeconds: end,
      ),
    );
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('削除しますか?'),
        content: const Text('このテキストを削除します。この操作は取り消せません。'),
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
    if (confirmed != true || !mounted) return;
    widget.onDelete?.call();
    Navigator.of(context).pop();
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
            // Tapping outside a field dismisses the keyboard, but this
            // must not cover the Save/Cancel row below: tapping Save pops
            // the sheet (disposing this State's TextEditingController),
            // and if this GestureDetector's onTap also fired for the same
            // tap, the resulting unfocus() notification could still be
            // pending when FocusManager processes it afterward, crashing
            // with "TextEditingController used after being disposed."
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => FocusScope.of(context).unfocus(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _controller,
                          autofocus: true,
                          decoration: const InputDecoration(labelText: 'テキスト'),
                          maxLines: 2,
                        ),
                      ),
                      if (widget.onDelete != null)
                        IconButton(
                          icon: const Icon(Icons.delete_outline),
                          tooltip: '削除',
                          onPressed: _confirmDelete,
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text('フォント', style: Theme.of(context).textTheme.labelLarge),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 56,
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
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: selected
                                  ? Theme.of(
                                      context,
                                    ).colorScheme.primaryContainer
                                  : Theme.of(
                                      context,
                                    ).colorScheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(8),
                              border: selected
                                  ? Border.all(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.primary,
                                      width: 2,
                                    )
                                  : null,
                            ),
                            child: Text(
                              'Pm 12:34 コメント',
                              style: TextStyle(
                                fontFamily: font.familyName,
                                fontSize: 15,
                              ),
                              maxLines: 1,
                              softWrap: false,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text('サイズ', style: Theme.of(context).textTheme.labelLarge),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final preset in _fontSizePresets)
                        ChoiceChip(
                          label: Text(preset.label),
                          selected: _fontSize == preset.value,
                          onSelected: (_) =>
                              setState(() => _fontSize = preset.value),
                        ),
                    ],
                  ),
                  Slider(
                    value: _fontSize,
                    min: 16,
                    max: 200,
                    onChanged: (v) => setState(() => _fontSize = v),
                  ),
                  const SizedBox(height: 8),
                  Text('配置', style: Theme.of(context).textTheme.labelLarge),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final preset in _positionPresets)
                        OutlinedButton(
                          onPressed: () => setState(() {
                            _x = preset.x;
                            _y = preset.y;
                          }),
                          child: Text(preset.label),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text('回転', style: Theme.of(context).textTheme.labelLarge),
                      const Spacer(),
                      Text('${_rotationDegrees.round()}°'),
                      IconButton(
                        icon: const Icon(Icons.rotate_right),
                        tooltip: '90度回転',
                        onPressed: () => setState(
                          () =>
                              _rotationDegrees = (_rotationDegrees + 90) % 360,
                        ),
                      ),
                    ],
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
                                width: _color.toARGB32() == c.toARGB32()
                                    ? 3
                                    : 1,
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
                  if (widget.showClipPicker &&
                      widget.clipBoundarySeconds.length > 1) ...[
                    const SizedBox(height: 16),
                    Text(
                      '表示するクリップ',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    Text(
                      '複数選ぶと、その間はずっと表示されます。',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    for (
                      var i = 0;
                      i < widget.clipBoundarySeconds.length - 1;
                      i++
                    )
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        title: Text(
                          'クリップ${i + 1} '
                          '(${formatSeconds(widget.clipBoundarySeconds[i])}〜'
                          '${formatSeconds(widget.clipBoundarySeconds[i + 1])})',
                        ),
                        value: _selectedClipIndices.contains(i),
                        onChanged: (_) => _toggleClip(i),
                      ),
                  ],
                  if (widget.showSecondsSlider) ...[
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '表示するタイミング',
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                        Text(
                          '${formatSeconds(_startSeconds)} 〜 ${formatSeconds(_endSeconds)}',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                    ),
                    _TimelineTicks(
                      totalSeconds: widget.totalSeconds,
                      boundarySeconds: widget.clipBoundarySeconds,
                    ),
                    RangeSlider(
                      values: RangeValues(_startSeconds, _endSeconds),
                      min: 0,
                      max: widget.totalSeconds > 0 ? widget.totalSeconds : 1,
                      onChanged: widget.totalSeconds <= 0
                          ? null
                          : (values) => setState(() {
                              _startSeconds = values.start;
                              _endSeconds = values.end;
                            }),
                    ),
                  ],
                ],
              ),
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

/// Thin vertical tick marks at each clip boundary, roughly aligned above a
/// [RangeSlider]'s track (Material centers the track within the slider's
/// full width, inset by its thumb radius on each side).
class _TimelineTicks extends StatelessWidget {
  const _TimelineTicks({
    required this.totalSeconds,
    required this.boundarySeconds,
  });

  final double totalSeconds;
  final List<double> boundarySeconds;

  static const _horizontalInset = 16.0;

  @override
  Widget build(BuildContext context) {
    if (totalSeconds <= 0) return const SizedBox(height: 12);
    return SizedBox(
      height: 12,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final trackWidth = (constraints.maxWidth - _horizontalInset * 2)
              .clamp(0.0, double.infinity);
          return Stack(
            children: [
              for (final boundary in boundarySeconds)
                if (boundary > 0 && boundary < totalSeconds)
                  Positioned(
                    left:
                        _horizontalInset +
                        (boundary / totalSeconds) * trackWidth -
                        0.5,
                    top: 0,
                    child: Container(
                      width: 1,
                      height: 10,
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                  ),
            ],
          );
        },
      ),
    );
  }
}
