import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../models/highlight_reel.dart';
import '../models/highlight_segment.dart';
import '../models/text_overlay.dart';
import 'video_thumbnail.dart';

/// A Premiere-style multi-track timeline for the 編集 screen: a time ruler,
/// a draggable playhead synced to [previewController], a video-clip track
/// (drag to reorder, drag either edge to re-trim), and one or more caption
/// tracks (drag either edge of a caption's bar to adjust its timing).
///
/// All drag interactions are purely local/visual until released — only the
/// final value is committed via the on*Commit callbacks, since committing a
/// clip trim re-encodes with ffmpeg and committing a caption edit re-runs
/// the whole compositing pipeline.
class VideoEditorTimeline extends StatefulWidget {
  const VideoEditorTimeline({
    super.key,
    required this.reel,
    required this.segments,
    required this.overlays,
    required this.previewController,
    required this.onReorderClip,
    required this.onCommitClipTrim,
    required this.selectedCaptionId,
    required this.onSelectCaption,
    required this.onTapCaption,
    required this.onCommitCaptionTiming,
    required this.onAddText,
    required this.onEditFraming,
    required this.onEditClipTiming,
    required this.onDeselectAll,
    required this.onCommitBgmTiming,
  });

  final HighlightReel reel;
  final List<HighlightSegment> segments;
  final List<TextOverlay> overlays;
  final VideoPlayerController? previewController;

  /// [newIndex] follows the same convention as [ReorderableListView]'s
  /// `onReorderItem`: the target index after [oldIndex] has been removed.
  final void Function(int oldIndex, int newIndex) onReorderClip;
  final void Function(
    int index, {
    Duration? newStartOffset,
    Duration? newDuration,
  })
  onCommitClipTrim;

  /// Id of the caption currently selected (shown as a draggable widget in
  /// the preview), or null if none. Owned by the parent since the preview
  /// needs to know it too.
  final String? selectedCaptionId;

  /// Fired when tapping an unselected caption bar — selects it without
  /// opening the edit form, so the first tap can be used to make the
  /// caption visible/positionable in the preview.
  final ValueChanged<String> onSelectCaption;

  /// Fired when tapping a caption bar that's already selected — opens the
  /// font/color/size/timing edit form.
  final ValueChanged<TextOverlay> onTapCaption;
  final void Function(TextOverlay overlay, double newStart, double newEnd)
  onCommitCaptionTiming;
  final VoidCallback onAddText;

  /// Opens the 画角編集 (framing) screen for the clip at this index —
  /// fired by the toolbar's crop/rotate icon, enabled only when a clip is
  /// selected.
  final ValueChanged<int> onEditFraming;

  /// Opens a numeric seconds-based alternative to dragging the clip's edges
  /// — fired by the toolbar's ruler icon, enabled only when a clip is
  /// selected.
  final ValueChanged<int> onEditClipTiming;

  /// Fired when tapping empty space in the timeline (not a clip block or
  /// caption bar) — clears the caption selection the parent owns; clip
  /// selection is cleared locally at the same time.
  final VoidCallback onDeselectAll;

  /// Fired when a drag on the BGM bar ends — [newStart] is where it now
  /// starts in the video's timeline, [newEnd] is where it stops (`null` =
  /// through to the end of the video).
  final void Function(double newStart, double? newEnd) onCommitBgmTiming;

  @override
  State<VideoEditorTimeline> createState() => _VideoEditorTimelineState();
}

class _VideoEditorTimelineState extends State<VideoEditorTimeline> {
  static const _rulerHeight = 20.0;
  static const _clipTrackHeight = 56.0;
  static const _bgmRowHeight = 32.0;
  static const _captionRowHeight = 40.0;
  static const _handleWidth = 22.0;
  static const _minZoom = 20.0;
  static const _maxZoom = 320.0;

  double _pixelsPerSecond = 80;
  final _scrollController = ScrollController();

  int? _selectedClipIndex;
  Duration? _selectedClipSourceDuration;

  // Clip drag state (reorder via body long-press, trim via edge handles).
  int? _draggingClipIndex;
  bool? _draggingClipLeftEdge;
  Duration _gestureStartOffset = Duration.zero;
  Duration _gestureStartDuration = Duration.zero;
  double _accumulatedDeltaSeconds = 0;
  Duration? _liveClipStartOffset;
  Duration? _liveClipDuration;
  double _reorderLiveDx = 0;
  int? _reorderTargetIndex;

  // BGM bar drag state (only one BGM track, so no id needed).
  bool _isDraggingBgm = false;
  bool? _draggingBgmLeftEdge;
  double _gestureStartBgmStart = 0;
  double _gestureStartBgmEnd = 0;
  double? _liveBgmStart;
  double? _liveBgmEnd;

  // Caption drag state.
  String? _draggingCaptionId;
  bool? _draggingCaptionLeftEdge;
  double _gestureStartCaptionStart = 0;
  double _gestureStartCaptionEnd = 0;
  double? _liveCaptionStart;
  double? _liveCaptionEnd;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  double get _tickIntervalSeconds {
    if (_pixelsPerSecond >= 150) return 1;
    if (_pixelsPerSecond >= 60) return 2;
    if (_pixelsPerSecond >= 30) return 5;
    return 10;
  }

  void _zoom(double factor) {
    setState(() {
      _pixelsPerSecond = (_pixelsPerSecond * factor).clamp(_minZoom, _maxZoom);
    });
  }

  /// Each segment's effective duration, substituting the live in-drag value
  /// for whichever clip is currently being trimmed.
  List<Duration> _effectiveDurations() {
    return [
      for (var i = 0; i < widget.segments.length; i++)
        if (i == _draggingClipIndex && _liveClipDuration != null)
          _liveClipDuration!
        else
          widget.segments[i].duration,
    ];
  }

  List<double> _clipStartXs(List<Duration> durations) {
    final xs = <double>[0];
    var cursor = 0.0;
    for (final d in durations) {
      cursor += d.inMilliseconds / 1000 * _pixelsPerSecond;
      xs.add(cursor);
    }
    return xs;
  }

  double get _totalSeconds {
    final durations = _effectiveDurations();
    final totalMs = durations.fold<int>(0, (sum, d) => sum + d.inMilliseconds);
    return totalMs / 1000;
  }

  double _contentWidth(double minWidth) {
    final needed = _totalSeconds * _pixelsPerSecond;
    return needed > minWidth ? needed : minWidth;
  }

  /// Cumulative clip boundaries in seconds (0, each clip's end, ...,
  /// total), used to snap a caption's dragged start/end to a nearby clip
  /// edge — a light bit of editing support so lining a caption up with a
  /// cut doesn't require a pixel-perfect drag.
  List<double> _clipBoundarySeconds() {
    final boundaries = <double>[0];
    var cursor = 0.0;
    for (final duration in _effectiveDurations()) {
      cursor += duration.inMilliseconds / 1000;
      boundaries.add(cursor);
    }
    return boundaries;
  }

  /// Snaps [seconds] to the nearest clip boundary if it's within a small
  /// on-screen distance (scaled by zoom so the snap always feels the same
  /// regardless of how zoomed in the timeline is), otherwise returns it
  /// unchanged.
  double _snapToClipBoundary(double seconds) {
    const snapPixels = 10.0;
    final thresholdSeconds = snapPixels / _pixelsPerSecond;
    var snapped = seconds;
    var closestDelta = thresholdSeconds;
    for (final boundary in _clipBoundarySeconds()) {
      final delta = (boundary - seconds).abs();
      if (delta <= closestDelta) {
        snapped = boundary;
        closestDelta = delta;
      }
    }
    return snapped;
  }

  // ---- Clip reorder (long-press + drag the block body) ----

  void _beginClipReorder(int index) {
    setState(() {
      _draggingClipIndex = index;
      _reorderLiveDx = 0;
      _reorderTargetIndex = index;
    });
  }

  void _updateClipReorder(int index, double offsetFromOriginDx) {
    final durations = _effectiveDurations();
    final xs = _clipStartXs(durations);
    final width = xs[index + 1] - xs[index];
    final liveCenter = xs[index] + width / 2 + offsetFromOriginDx;

    var target = index;
    for (var i = 0; i < widget.segments.length; i++) {
      final center = (xs[i] + xs[i + 1]) / 2;
      if (liveCenter >= center) target = i;
    }

    setState(() {
      _reorderLiveDx = offsetFromOriginDx;
      _reorderTargetIndex = target;
    });
  }

  void _endClipReorder(int index) {
    final target = _reorderTargetIndex;
    setState(() {
      _draggingClipIndex = null;
      _reorderLiveDx = 0;
      _reorderTargetIndex = null;
    });
    if (target != null && target != index) {
      widget.onReorderClip(index, target);
    }
  }

  void _cancelClipReorder() {
    setState(() {
      _draggingClipIndex = null;
      _reorderLiveDx = 0;
      _reorderTargetIndex = null;
    });
  }

  // ---- Clip trim (drag the edge handles) ----

  Future<void> _selectClip(int index) async {
    setState(() {
      _selectedClipIndex = index;
      _selectedClipSourceDuration = null;
    });
    final duration = await widget.reel.sourceDurationFor(
      widget.segments[index],
    );
    if (!mounted || _selectedClipIndex != index) return;
    setState(() => _selectedClipSourceDuration = duration);
  }

  /// Clears both clip and caption selection — fired when tapping empty
  /// timeline space (not a clip block or caption bar).
  void _deselectAll() {
    if (_selectedClipIndex != null) {
      setState(() {
        _selectedClipIndex = null;
        _selectedClipSourceDuration = null;
      });
    }
    if (widget.selectedCaptionId != null) {
      widget.onDeselectAll();
    }
  }

  void _beginClipTrim(int index, {required bool leftEdge}) {
    final segment = widget.segments[index];
    setState(() {
      _draggingClipIndex = index;
      _draggingClipLeftEdge = leftEdge;
      _gestureStartOffset = segment.startOffset;
      _gestureStartDuration = segment.duration;
      _accumulatedDeltaSeconds = 0;
      _liveClipStartOffset = segment.startOffset;
      _liveClipDuration = segment.duration;
    });
  }

  void _updateClipTrim(int index, double deltaDx) {
    _accumulatedDeltaSeconds += deltaDx / _pixelsPerSecond;
    final deltaMs = (_accumulatedDeltaSeconds * 1000).round();
    const minDuration = Duration(milliseconds: 200);
    final sourceMax = _selectedClipSourceDuration ?? _gestureStartDuration;

    Duration newOffset;
    Duration newDuration;
    if (_draggingClipLeftEdge == true) {
      final sourceEndMs =
          _gestureStartOffset.inMilliseconds +
          _gestureStartDuration.inMilliseconds;
      var offsetMs = _gestureStartOffset.inMilliseconds + deltaMs;
      offsetMs = offsetMs.clamp(0, sourceEndMs - minDuration.inMilliseconds);
      newOffset = Duration(milliseconds: offsetMs);
      newDuration = Duration(milliseconds: sourceEndMs - offsetMs);
    } else {
      var durationMs = _gestureStartDuration.inMilliseconds + deltaMs;
      final maxDurationMs =
          sourceMax.inMilliseconds - _gestureStartOffset.inMilliseconds;
      durationMs = durationMs.clamp(
        minDuration.inMilliseconds,
        maxDurationMs < minDuration.inMilliseconds
            ? minDuration.inMilliseconds
            : maxDurationMs,
      );
      newOffset = _gestureStartOffset;
      newDuration = Duration(milliseconds: durationMs);
    }

    setState(() {
      _liveClipStartOffset = newOffset;
      _liveClipDuration = newDuration;
    });
  }

  void _endClipTrim(int index) {
    final offset = _liveClipStartOffset;
    final duration = _liveClipDuration;
    setState(() {
      _draggingClipIndex = null;
      _draggingClipLeftEdge = null;
      _liveClipStartOffset = null;
      _liveClipDuration = null;
    });
    if (offset != null && duration != null) {
      widget.onCommitClipTrim(
        index,
        newStartOffset: offset,
        newDuration: duration,
      );
    }
  }

  void _cancelClipTrim() {
    setState(() {
      _draggingClipIndex = null;
      _draggingClipLeftEdge = null;
      _liveClipStartOffset = null;
      _liveClipDuration = null;
    });
  }

  // ---- BGM bar drag (mirrors the caption drag below: long-press + move,
  // either edge to trim or the body to shift the whole placed span) ----

  void _beginBgmDrag({bool? leftEdge}) {
    setState(() {
      _isDraggingBgm = true;
      _draggingBgmLeftEdge = leftEdge;
      _gestureStartBgmStart = widget.reel.bgmStartSeconds;
      _gestureStartBgmEnd = widget.reel.bgmEndSeconds ?? _totalSeconds;
      _liveBgmStart = _gestureStartBgmStart;
      _liveBgmEnd = _gestureStartBgmEnd;
    });
  }

  void _updateBgmDrag(double totalDx) {
    final deltaSeconds = totalDx / _pixelsPerSecond;
    const minGap = 0.5;
    var start = _gestureStartBgmStart;
    var end = _gestureStartBgmEnd;
    if (_draggingBgmLeftEdge == true) {
      start = (_gestureStartBgmStart + deltaSeconds).clamp(
        0.0,
        _gestureStartBgmEnd - minGap,
      );
    } else if (_draggingBgmLeftEdge == false) {
      end = (_gestureStartBgmEnd + deltaSeconds).clamp(
        _gestureStartBgmStart + minGap,
        _totalSeconds,
      );
    } else {
      final duration = _gestureStartBgmEnd - _gestureStartBgmStart;
      final shift = deltaSeconds.clamp(
        -_gestureStartBgmStart,
        _totalSeconds - _gestureStartBgmEnd,
      );
      start = _gestureStartBgmStart + shift;
      end = start + duration;
    }
    setState(() {
      _liveBgmStart = start;
      _liveBgmEnd = end;
    });
  }

  void _endBgmDrag() {
    final start = _liveBgmStart;
    final end = _liveBgmEnd;
    setState(() {
      _isDraggingBgm = false;
      _draggingBgmLeftEdge = null;
      _liveBgmStart = null;
      _liveBgmEnd = null;
    });
    if (start != null && end != null) {
      widget.onCommitBgmTiming(start, end >= _totalSeconds - 0.05 ? null : end);
    }
  }

  void _cancelBgmDrag() {
    setState(() {
      _isDraggingBgm = false;
      _draggingBgmLeftEdge = null;
      _liveBgmStart = null;
      _liveBgmEnd = null;
    });
  }

  // ---- Caption timing drag (long-press + move, mirroring the clip block's
  // proven long-press-based reorder gesture so it doesn't compete with the
  // ancestor horizontal ScrollView's own drag-to-scroll recognizer) ----
  // _draggingCaptionLeftEdge: true = resize left edge, false = resize right
  // edge, null = move the whole bar (both edges shift together).

  void _beginCaptionDrag(TextOverlay overlay, {bool? leftEdge}) {
    setState(() {
      _draggingCaptionId = overlay.id;
      _draggingCaptionLeftEdge = leftEdge;
      _gestureStartCaptionStart = overlay.startSeconds;
      _gestureStartCaptionEnd = overlay.endSeconds;
      _liveCaptionStart = overlay.startSeconds;
      _liveCaptionEnd = overlay.endSeconds;
    });
  }

  /// [totalDx] is the cumulative horizontal offset since the long-press was
  /// recognized (LongPressMoveUpdateDetails.offsetFromOrigin), not a
  /// per-frame delta, so it's applied directly to the gesture's starting
  /// values rather than accumulated.
  void _updateCaptionDrag(double totalDx) {
    final deltaSeconds = totalDx / _pixelsPerSecond;
    const minGap = 0.2;
    var start = _gestureStartCaptionStart;
    var end = _gestureStartCaptionEnd;
    if (_draggingCaptionLeftEdge == true) {
      start = (_gestureStartCaptionStart + deltaSeconds).clamp(
        0.0,
        _gestureStartCaptionEnd - minGap,
      );
      start = _snapToClipBoundary(start).clamp(0.0, end - minGap);
    } else if (_draggingCaptionLeftEdge == false) {
      end = (_gestureStartCaptionEnd + deltaSeconds).clamp(
        _gestureStartCaptionStart + minGap,
        _totalSeconds,
      );
      end = _snapToClipBoundary(end).clamp(start + minGap, _totalSeconds);
    } else {
      final duration = _gestureStartCaptionEnd - _gestureStartCaptionStart;
      final shift = deltaSeconds.clamp(
        -_gestureStartCaptionStart,
        _totalSeconds - _gestureStartCaptionEnd,
      );
      start = _gestureStartCaptionStart + shift;
      end = start + duration;
      // Snap whichever edge lands closest to a clip boundary, shifting
      // the other edge along with it to keep the caption's duration fixed.
      final startSnapDelta = (_snapToClipBoundary(start) - start).abs();
      final endSnapDelta = (_snapToClipBoundary(end) - end).abs();
      if (startSnapDelta > 0 && startSnapDelta <= endSnapDelta) {
        final snapped = _snapToClipBoundary(start);
        end += snapped - start;
        start = snapped;
      } else if (endSnapDelta > 0) {
        final snapped = _snapToClipBoundary(end);
        start += snapped - end;
        end = snapped;
      }
    }
    setState(() {
      _liveCaptionStart = start;
      _liveCaptionEnd = end;
    });
  }

  void _endCaptionDrag(TextOverlay overlay) {
    final start = _liveCaptionStart;
    final end = _liveCaptionEnd;
    setState(() {
      _draggingCaptionId = null;
      _draggingCaptionLeftEdge = null;
      _liveCaptionStart = null;
      _liveCaptionEnd = null;
    });
    if (start != null && end != null) {
      widget.onCommitCaptionTiming(overlay, start, end);
    }
  }

  void _cancelCaptionDrag() {
    setState(() {
      _draggingCaptionId = null;
      _draggingCaptionLeftEdge = null;
      _liveCaptionStart = null;
      _liveCaptionEnd = null;
    });
  }

  /// First tap on a caption bar selects it (so it becomes visible/
  /// draggable in the preview); tapping the already-selected bar again
  /// opens the edit form instead.
  void _handleCaptionTap(TextOverlay overlay) {
    if (widget.selectedCaptionId == overlay.id) {
      widget.onTapCaption(overlay);
    } else {
      widget.onSelectCaption(overlay.id);
    }
  }

  // ---- Playhead ----

  void _seekToDx(double dx) {
    final controller = widget.previewController;
    if (controller == null || !controller.value.isInitialized) return;
    final totalMs = (_totalSeconds * 1000).round();
    if (totalMs <= 0) return;
    final ms = (dx / _pixelsPerSecond * 1000).round().clamp(0, totalMs);
    controller.seekTo(Duration(milliseconds: ms));
  }

  @override
  Widget build(BuildContext context) {
    final rows = _layoutCaptionRows(widget.overlays);
    final hasBgm = widget.reel.bgmFile != null;
    final trackHeight =
        _rulerHeight +
        _clipTrackHeight +
        (hasBgm ? _bgmRowHeight : 0) +
        rows.length * _captionRowHeight;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Text('タイムライン', style: Theme.of(context).textTheme.labelLarge),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.zoom_out),
                onPressed: () => _zoom(1 / 1.4),
                visualDensity: VisualDensity.compact,
              ),
              IconButton(
                icon: const Icon(Icons.zoom_in),
                onPressed: () => _zoom(1.4),
                visualDensity: VisualDensity.compact,
              ),
              IconButton(
                icon: const Icon(Icons.add_box_outlined),
                tooltip: 'テキストを追加',
                onPressed: widget.onAddText,
                visualDensity: VisualDensity.compact,
              ),
              IconButton(
                icon: const Icon(Icons.crop_rotate),
                tooltip: '画角編集',
                onPressed: _selectedClipIndex == null
                    ? null
                    : () => widget.onEditFraming(_selectedClipIndex!),
                visualDensity: VisualDensity.compact,
              ),
              IconButton(
                icon: const Icon(Icons.straighten),
                tooltip: '秒数調整',
                onPressed: _selectedClipIndex == null
                    ? null
                    : () => widget.onEditClipTiming(_selectedClipIndex!),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ),
        if (widget.segments.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text('まだクリップがありません'),
          )
        else
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            // A vertical SingleChildScrollView was tried here as a safety
            // net for many overlapping caption rows, but nesting it around
            // the horizontal one confused the gesture arena enough that
            // dragging the clip/caption handles stopped working reliably.
            // Overlapping captions are rare enough that it's not worth
            // reintroducing that risk to guard against it.
            child: LayoutBuilder(
              builder: (context, constraints) {
                final contentWidth = _contentWidth(constraints.maxWidth);
                return SingleChildScrollView(
                  controller: _scrollController,
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: contentWidth,
                    height: trackHeight,
                    child: Stack(
                      children: [
                        // Tapping empty space (not a clip block or caption
                        // bar — those have their own GestureDetectors on
                        // top of this and win the hit test) deselects.
                        Positioned.fill(
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: _deselectAll,
                          ),
                        ),
                        Column(
                          children: [
                            _buildRuler(contentWidth),
                            _buildClipTrack(contentWidth),
                            if (hasBgm) _buildBgmRow(contentWidth),
                            for (final row in rows)
                              _buildCaptionRow(row, contentWidth),
                          ],
                        ),
                        _buildPlayhead(trackHeight),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _buildRuler(double width) {
    final ticks = <Widget>[];
    final interval = _tickIntervalSeconds;
    for (var t = 0.0; t <= _totalSeconds + 0.001; t += interval) {
      ticks.add(
        Positioned(
          left: t * _pixelsPerSecond,
          top: 0,
          child: Text(
            '${t.toStringAsFixed(interval < 1 ? 1 : 0)}s',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(fontSize: 10),
          ),
        ),
      );
    }
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (details) => _seekToDx(details.localPosition.dx),
      onHorizontalDragStart: (details) => _seekToDx(details.localPosition.dx),
      onHorizontalDragUpdate: (details) => _seekToDx(details.localPosition.dx),
      child: SizedBox(
        width: width,
        height: _rulerHeight,
        child: Stack(children: ticks),
      ),
    );
  }

  Widget _buildClipTrack(double width) {
    final durations = _effectiveDurations();
    final xs = _clipStartXs(durations);
    return SizedBox(
      width: width,
      height: _clipTrackHeight,
      child: Stack(
        children: [
          for (var i = 0; i < widget.segments.length; i++)
            _buildClipBlock(i, xs[i], xs[i + 1] - xs[i]),
        ],
      ),
    );
  }

  Widget _buildClipBlock(int index, double left, double width) {
    final segment = widget.segments[index];
    final selected = _selectedClipIndex == index;
    final isReordering =
        _draggingClipIndex == index && _draggingClipLeftEdge == null;
    final isTrimming =
        _draggingClipIndex == index && _draggingClipLeftEdge != null;
    final showInsertionMark =
        _reorderTargetIndex == index && _draggingClipIndex != index;

    return Positioned(
      left: left + (isReordering ? _reorderLiveDx : 0),
      top: 2,
      width: width.clamp(_handleWidth * 2, double.infinity),
      height: _clipTrackHeight - 4,
      child: GestureDetector(
        onTap: () => _selectClip(index),
        onLongPressStart: (_) => _beginClipReorder(index),
        onLongPressMoveUpdate: (details) =>
            _updateClipReorder(index, details.offsetFromOrigin.dx),
        onLongPressEnd: (_) => _endClipReorder(index),
        onLongPressCancel: _cancelClipReorder,
        child: AnimatedOpacity(
          opacity: isReordering ? 0.75 : 1,
          duration: const Duration(milliseconds: 100),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: selected || showInsertionMark
                    ? Theme.of(context).colorScheme.primary
                    : Colors.black26,
                width: selected || showInsertionMark ? 2 : 1,
              ),
              boxShadow: isReordering
                  ? const [
                      BoxShadow(
                        color: Colors.black45,
                        blurRadius: 6,
                        offset: Offset(0, 2),
                      ),
                    ]
                  : null,
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              children: [
                Positioned.fill(
                  child: VideoThumbnail(
                    file: segment.file,
                    width: width.clamp(_handleWidth * 2, double.infinity),
                    height: _clipTrackHeight - 4,
                  ),
                ),
                Positioned(
                  left: 3,
                  bottom: 2,
                  child: Text(
                    '${((isTrimming ? _liveClipDuration! : segment.duration).inMilliseconds / 1000).toStringAsFixed(1)}s',
                    style: const TextStyle(
                      fontSize: 9,
                      color: Colors.white,
                      shadows: [Shadow(blurRadius: 2, color: Colors.black)],
                    ),
                  ),
                ),
                if (selected) ...[
                  _clipTrimHandle(
                    index: index,
                    leftEdge: true,
                    alignment: Alignment.centerLeft,
                  ),
                  _clipTrimHandle(
                    index: index,
                    leftEdge: false,
                    alignment: Alignment.centerRight,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _clipTrimHandle({
    required int index,
    required bool leftEdge,
    required Alignment alignment,
  }) {
    return Align(
      alignment: alignment,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (_) => _beginClipTrim(index, leftEdge: leftEdge),
        onPanUpdate: (details) => _updateClipTrim(index, details.delta.dx),
        onPanEnd: (_) => _endClipTrim(index),
        onPanCancel: _cancelClipTrim,
        child: Container(
          width: _handleWidth,
          color: Colors.black45,
          child: const Icon(
            Icons.drag_indicator,
            size: 14,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  Widget _buildBgmRow(double width) {
    final reel = widget.reel;
    final start = _isDraggingBgm
        ? _liveBgmStart ?? reel.bgmStartSeconds
        : reel.bgmStartSeconds;
    final end = _isDraggingBgm
        ? _liveBgmEnd ?? (reel.bgmEndSeconds ?? _totalSeconds)
        : (reel.bgmEndSeconds ?? _totalSeconds);
    final left = start * _pixelsPerSecond;
    final barWidth = ((end - start) * _pixelsPerSecond).clamp(
      _handleWidth * 2,
      double.infinity,
    );

    return SizedBox(
      width: width,
      height: _bgmRowHeight,
      child: Stack(
        children: [
          Positioned(
            left: left,
            top: 2,
            width: barWidth,
            height: _bgmRowHeight - 4,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.teal.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.black26),
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onLongPressStart: (_) => _beginBgmDrag(),
                      onLongPressMoveUpdate: (details) =>
                          _updateBgmDrag(details.offsetFromOrigin.dx),
                      onLongPressEnd: (_) => _endBgmDrag(),
                      onLongPressCancel: _cancelBgmDrag,
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: _handleWidth + 2,
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.music_note,
                              size: 12,
                              color: Colors.white,
                            ),
                            const SizedBox(width: 2),
                            Expanded(
                              child: Text(
                                reel.bgmTitle ?? 'BGM',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onLongPressStart: (_) => _beginBgmDrag(leftEdge: true),
                      onLongPressMoveUpdate: (details) =>
                          _updateBgmDrag(details.offsetFromOrigin.dx),
                      onLongPressEnd: (_) => _endBgmDrag(),
                      onLongPressCancel: _cancelBgmDrag,
                      child: Container(
                        width: _handleWidth,
                        color: Colors.black26,
                        child: const Icon(
                          Icons.drag_indicator,
                          size: 14,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onLongPressStart: (_) => _beginBgmDrag(leftEdge: false),
                      onLongPressMoveUpdate: (details) =>
                          _updateBgmDrag(details.offsetFromOrigin.dx),
                      onLongPressEnd: (_) => _endBgmDrag(),
                      onLongPressCancel: _cancelBgmDrag,
                      child: Container(
                        width: _handleWidth,
                        color: Colors.black26,
                        child: const Icon(
                          Icons.drag_indicator,
                          size: 14,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<List<TextOverlay>> _layoutCaptionRows(List<TextOverlay> overlays) {
    final rows = <List<TextOverlay>>[];
    final sorted = [...overlays]
      ..sort((a, b) => a.startSeconds.compareTo(b.startSeconds));
    for (final overlay in sorted) {
      final row = rows.firstWhere(
        (row) => row.every(
          (existing) =>
              overlay.startSeconds >= existing.endSeconds ||
              overlay.endSeconds <= existing.startSeconds,
        ),
        orElse: () {
          final newRow = <TextOverlay>[];
          rows.add(newRow);
          return newRow;
        },
      );
      row.add(overlay);
    }
    return rows;
  }

  Widget _buildCaptionRow(List<TextOverlay> overlays, double width) {
    return SizedBox(
      width: width,
      height: _captionRowHeight,
      child: Stack(
        children: [for (final overlay in overlays) _buildCaptionBar(overlay)],
      ),
    );
  }

  Widget _buildCaptionBar(TextOverlay overlay) {
    final dragging = _draggingCaptionId == overlay.id;
    final selected = widget.selectedCaptionId == overlay.id;
    final start = dragging
        ? _liveCaptionStart ?? overlay.startSeconds
        : overlay.startSeconds;
    final end = dragging
        ? _liveCaptionEnd ?? overlay.endSeconds
        : overlay.endSeconds;
    final left = start * _pixelsPerSecond;
    final width = ((end - start) * _pixelsPerSecond).clamp(
      _handleWidth * 2,
      double.infinity,
    );
    final textColor = overlay.color.computeLuminance() > 0.5
        ? Colors.black
        : Colors.white;

    return Positioned(
      left: left,
      top: 2,
      width: width,
      height: _captionRowHeight - 4,
      child: Container(
        decoration: BoxDecoration(
          color: overlay.color.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: selected
                ? Theme.of(context).colorScheme.primary
                : Colors.black26,
            width: selected ? 2 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _handleCaptionTap(overlay),
                onLongPressStart: (_) => _beginCaptionDrag(overlay),
                onLongPressMoveUpdate: (details) =>
                    _updateCaptionDrag(details.offsetFromOrigin.dx),
                onLongPressEnd: (_) => _endCaptionDrag(overlay),
                onLongPressCancel: _cancelCaptionDrag,
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: _handleWidth + 2),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      overlay.text,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, color: textColor),
                    ),
                  ),
                ),
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onLongPressStart: (_) =>
                    _beginCaptionDrag(overlay, leftEdge: true),
                onLongPressMoveUpdate: (details) =>
                    _updateCaptionDrag(details.offsetFromOrigin.dx),
                onLongPressEnd: (_) => _endCaptionDrag(overlay),
                onLongPressCancel: _cancelCaptionDrag,
                child: Container(
                  width: _handleWidth,
                  color: Colors.black26,
                  child: Icon(Icons.drag_indicator, size: 14, color: textColor),
                ),
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onLongPressStart: (_) =>
                    _beginCaptionDrag(overlay, leftEdge: false),
                onLongPressMoveUpdate: (details) =>
                    _updateCaptionDrag(details.offsetFromOrigin.dx),
                onLongPressEnd: (_) => _endCaptionDrag(overlay),
                onLongPressCancel: _cancelCaptionDrag,
                child: Container(
                  width: _handleWidth,
                  color: Colors.black26,
                  child: Icon(Icons.drag_indicator, size: 14, color: textColor),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlayhead(double height) {
    final controller = widget.previewController;
    if (controller == null) return const SizedBox.shrink();
    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        final seconds = value.position.inMilliseconds / 1000;
        final x = seconds * _pixelsPerSecond;
        return Positioned(
          left: x - 1,
          top: 0,
          height: height,
          child: IgnorePointer(
            child: Container(
              width: 2,
              color: Theme.of(context).colorScheme.error,
            ),
          ),
        );
      },
    );
  }
}
