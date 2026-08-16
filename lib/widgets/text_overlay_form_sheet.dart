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
/// color, and visible time range. Shared by the まとめ tab (簡易編集: add and
/// manage captions from a plain list) and the 編集 tab (its timeline opens
/// this for font/color/size changes; position/rotation/timing are also
/// adjustable directly on the 編集 tab's canvas/timeline).
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
    this.onDelete,
  });

  final TextOverlay initial;

  /// Total duration of the compiled video (pre-BGM/text), in seconds.
  final double totalSeconds;

  /// Cumulative clip start times (seconds), including 0 and [totalSeconds],
  /// used to draw tick marks on the timeline for reference.
  final List<double> clipBoundarySeconds;

  final VoidCallback? onDelete;

  @override
  State<TextOverlayFormSheet> createState() => _TextOverlayFormSheetState();
}

class _TextOverlayFormSheetState extends State<TextOverlayFormSheet> {
  late final TextEditingController _controller;
  late String _fontId;
  late double _fontSize;
  late Color _color;
  late double _startSeconds;
  late double _endSeconds;

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
    final maxSeconds = widget.totalSeconds > 0 ? widget.totalSeconds : 0.0;
    _startSeconds = widget.initial.startSeconds.clamp(0.0, maxSeconds);
    _endSeconds = widget.initial.endSeconds.clamp(0.0, maxSeconds);
    if (_startSeconds > _endSeconds) _startSeconds = _endSeconds;
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
            Text(
              '縦の点線はクリップの区切りです。ドラッグして自由に表示区間を決められます。',
              style: Theme.of(context).textTheme.bodySmall,
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
  const _TimelineTicks({required this.totalSeconds, required this.boundarySeconds});

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
