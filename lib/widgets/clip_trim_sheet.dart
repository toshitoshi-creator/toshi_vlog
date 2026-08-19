import 'package:flutter/material.dart';

import '../models/highlight_reel.dart';
import 'text_overlay_form_sheet.dart' show formatSeconds;

/// Modal bottom sheet giving a numeric alternative to dragging clip [index]'s
/// edges on the 編集 tab's timeline: sliders (with an exact seconds readout)
/// for where the clip starts within its source recording and how long it
/// runs, writing straight through to [reel] via [HighlightReel.trimSegment]
/// on save — the same call the timeline's drag handles use.
class ClipTrimSheet extends StatefulWidget {
  const ClipTrimSheet({super.key, required this.reel, required this.index});

  final HighlightReel reel;
  final int index;

  @override
  State<ClipTrimSheet> createState() => _ClipTrimSheetState();
}

class _ClipTrimSheetState extends State<ClipTrimSheet> {
  double? _sourceDurationSeconds;
  late double _startOffsetSeconds;
  late double _durationSeconds;

  static const _minDurationSeconds = 0.2;

  @override
  void initState() {
    super.initState();
    final segment = widget.reel.segments[widget.index];
    _startOffsetSeconds = segment.startOffset.inMilliseconds / 1000;
    _durationSeconds = segment.duration.inMilliseconds / 1000;
    _loadSourceDuration();
  }

  Future<void> _loadSourceDuration() async {
    final segment = widget.reel.segments[widget.index];
    final duration = await widget.reel.sourceDurationFor(segment);
    if (!mounted) return;
    setState(() {
      _sourceDurationSeconds = duration.inMilliseconds / 1000;
    });
  }

  double get _maxDurationForStart {
    final sourceMax = _sourceDurationSeconds ?? _startOffsetSeconds;
    final max = sourceMax - _startOffsetSeconds;
    return max < _minDurationSeconds ? _minDurationSeconds : max;
  }

  void _setStartOffset(double v) {
    setState(() {
      _startOffsetSeconds = v;
      if (_durationSeconds > _maxDurationForStart) {
        _durationSeconds = _maxDurationForStart;
      }
    });
  }

  Future<void> _save() async {
    await widget.reel.trimSegment(
      widget.index,
      newStartOffset: Duration(
        milliseconds: (_startOffsetSeconds * 1000).round(),
      ),
      newDuration: Duration(milliseconds: (_durationSeconds * 1000).round()),
    );
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final sourceMax = _sourceDurationSeconds;
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: sourceMax == null
          ? const SizedBox(
              height: 120,
              child: Center(child: CircularProgressIndicator()),
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'クリップの秒数調整',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '元動画内の開始位置',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    Text(formatSeconds(_startOffsetSeconds)),
                  ],
                ),
                Slider(
                  value: _startOffsetSeconds.clamp(0.0, sourceMax),
                  min: 0,
                  max: sourceMax,
                  onChanged: _setStartOffset,
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('長さ', style: Theme.of(context).textTheme.labelLarge),
                    Text('${_durationSeconds.toStringAsFixed(1)}秒'),
                  ],
                ),
                Slider(
                  value: _durationSeconds.clamp(
                    _minDurationSeconds,
                    _maxDurationForStart,
                  ),
                  min: _minDurationSeconds,
                  max: _maxDurationForStart,
                  onChanged: (v) => setState(() => _durationSeconds = v),
                ),
                const SizedBox(height: 16),
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
    );
  }
}
