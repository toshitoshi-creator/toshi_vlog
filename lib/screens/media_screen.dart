import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/video_item.dart';
import '../models/video_library.dart';
import '../widgets/video_thumbnail.dart';
import 'video_player_screen.dart';

class MediaScreen extends StatefulWidget {
  const MediaScreen({super.key, required this.videoLibrary});

  final VideoLibrary videoLibrary;

  @override
  State<MediaScreen> createState() => _MediaScreenState();
}

class _MediaScreenState extends State<MediaScreen> {
  DateTime? _selectedDate;

  /// Whether the list is showing per-item checkboxes for bulk delete.
  bool _isSelecting = false;
  final Set<String> _selectedPaths = {};

  @override
  void initState() {
    super.initState();
    widget.videoLibrary.addListener(_onLibraryChanged);
    widget.videoLibrary.reload();
  }

  @override
  void dispose() {
    widget.videoLibrary.removeListener(_onLibraryChanged);
    super.dispose();
  }

  void _onLibraryChanged() {
    if (mounted) setState(() {});
  }

  void _toggleSelectionMode() {
    setState(() {
      _isSelecting = !_isSelecting;
      _selectedPaths.clear();
    });
  }

  void _toggleSelected(VideoItem video) {
    setState(() {
      if (!_selectedPaths.remove(video.file.path)) {
        _selectedPaths.add(video.file.path);
      }
    });
  }

  /// Shows a confirmation dialog for [items], and only actually deletes if
  /// the user taps 削除 — used by all three bulk-delete entry points
  /// (selection, day, month), which are all destructive and irreversible.
  Future<void> _confirmAndDelete(List<VideoItem> items, String message) async {
    if (items.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('削除しますか?'),
        content: Text(message),
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
    await widget.videoLibrary.deleteAll(items);
    if (mounted) {
      setState(() {
        _isSelecting = false;
        _selectedPaths.clear();
      });
    }
  }

  Future<void> _handleDeleteSelected() async {
    final items = widget.videoLibrary.videos
        .where((v) => _selectedPaths.contains(v.file.path))
        .toList();
    await _confirmAndDelete(
      items,
      '選択した${items.length}件の動画を削除します。この操作は取り消せません。',
    );
  }

  Future<void> _handleDeleteDay(DateTime day, List<VideoItem> videosForDay) {
    return _confirmAndDelete(
      videosForDay,
      '${DateFormat('yyyy/MM/dd').format(day)}の動画'
      '(${videosForDay.length}件)をすべて削除します。この操作は取り消せません。',
    );
  }

  Future<void> _handleDeleteMonth(DateTime day) {
    final items = widget.videoLibrary.videos
        .where(
          (v) => v.createdAt.year == day.year && v.createdAt.month == day.month,
        )
        .toList();
    return _confirmAndDelete(
      items,
      '${DateFormat('yyyy年M月').format(day)}の動画'
      '(${items.length}件)をすべて削除します。この操作は取り消せません。',
    );
  }

  List<DateTime> get _availableDates {
    final days = widget.videoLibrary.videos.map(_dayOf).toSet().toList()
      ..sort();
    return days;
  }

  DateTime _dayOf(VideoItem video) {
    final createdAt = video.createdAt;
    return DateTime(createdAt.year, createdAt.month, createdAt.day);
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  @override
  Widget build(BuildContext context) {
    final dates = _availableDates;
    final selected = _selectedDate ?? (dates.isNotEmpty ? dates.last : null);
    final videosForDay = selected == null
        ? const <VideoItem>[]
        : widget.videoLibrary.videos
              .where((video) => _isSameDay(_dayOf(video), selected))
              .toList();

    return Scaffold(
      appBar: AppBar(
        title: _isSelecting
            ? Text('${_selectedPaths.length}件選択中')
            : const Text('メディア'),
        leading: _isSelecting
            ? IconButton(
                icon: const Icon(Icons.close),
                tooltip: '選択を終了',
                onPressed: _toggleSelectionMode,
              )
            : null,
        actions: _isSelecting
            ? [
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: '選択した動画を削除',
                  onPressed: _selectedPaths.isEmpty
                      ? null
                      : _handleDeleteSelected,
                ),
              ]
            : [
                IconButton(
                  icon: const Icon(Icons.checklist),
                  tooltip: '複数選択して削除',
                  onPressed: dates.isEmpty ? null : _toggleSelectionMode,
                ),
                PopupMenuButton<String>(
                  enabled: selected != null,
                  tooltip: 'まとめて削除',
                  onSelected: (value) {
                    if (value == 'day') {
                      _handleDeleteDay(selected!, videosForDay);
                    } else if (value == 'month') {
                      _handleDeleteMonth(selected!);
                    }
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(value: 'day', child: Text('この日の動画をすべて削除')),
                    PopupMenuItem(value: 'month', child: Text('この月の動画をすべて削除')),
                  ],
                ),
              ],
      ),
      body: RefreshIndicator(
        onRefresh: widget.videoLibrary.reload,
        child: Column(
          children: [
            if (dates.isNotEmpty)
              _DateScroller(
                dates: dates,
                selected: selected,
                onSelect: (date) => setState(() => _selectedDate = date),
              ),
            if (dates.isNotEmpty) const Divider(height: 1),
            Expanded(
              child: dates.isEmpty
                  ? ListView(
                      children: const [
                        SizedBox(height: 120),
                        Icon(Icons.videocam_off, size: 48, color: Colors.grey),
                        SizedBox(height: 16),
                        Center(child: Text('動画がありません')),
                        SizedBox(height: 8),
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: 32),
                          child: Text(
                            'カメラタブで撮影すると、ここに日付ごとに表示されます',
                            style: TextStyle(color: Colors.grey),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    )
                  : videosForDay.isEmpty
                  ? const Center(child: Text('この日の動画はありません'))
                  : ListView.builder(
                      itemCount: videosForDay.length,
                      itemBuilder: (context, index) {
                        final video = videosForDay[index];
                        final isSelected = _selectedPaths.contains(
                          video.file.path,
                        );
                        final tile = ListTile(
                          leading: VideoThumbnail(file: video.file),
                          title: Text(
                            DateFormat('HH:mm').format(video.createdAt),
                          ),
                          subtitle: Text(_formatDuration(video.duration)),
                          selected: isSelected,
                          trailing: _isSelecting
                              ? Checkbox(
                                  value: isSelected,
                                  onChanged: (_) => _toggleSelected(video),
                                )
                              : null,
                          onTap: _isSelecting
                              ? () => _toggleSelected(video)
                              : () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => VideoPlayerScreen(
                                        file: video.file,
                                        title: DateFormat(
                                          'yyyy/MM/dd HH:mm',
                                        ).format(video.createdAt),
                                      ),
                                    ),
                                  );
                                },
                        );
                        if (_isSelecting) return tile;
                        return Dismissible(
                          key: ValueKey(video.file.path),
                          direction: DismissDirection.endToStart,
                          background: Container(
                            color: Colors.red,
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            child: const Icon(
                              Icons.delete,
                              color: Colors.white,
                            ),
                          ),
                          onDismissed: (_) => widget.videoLibrary.delete(video),
                          child: tile,
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}

class _DateScroller extends StatefulWidget {
  const _DateScroller({
    required this.dates,
    required this.selected,
    required this.onSelect,
  });

  final List<DateTime> dates;
  final DateTime? selected;
  final ValueChanged<DateTime> onSelect;

  @override
  State<_DateScroller> createState() => _DateScrollerState();
}

class _DateScrollerState extends State<_DateScroller> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToSelected());
  }

  void _scrollToSelected() {
    if (!_scrollController.hasClients) return;
    final index = widget.dates.indexWhere(
      (date) =>
          widget.selected != null &&
          date.year == widget.selected!.year &&
          date.month == widget.selected!.month &&
          date.day == widget.selected!.day,
    );
    if (index < 0) return;
    const itemExtent = 72.0;
    final offset = (index * itemExtent - 100).clamp(
      0.0,
      _scrollController.position.maxScrollExtent,
    );
    _scrollController.jumpTo(offset);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 72,
      child: ListView.separated(
        controller: _scrollController,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        scrollDirection: Axis.horizontal,
        itemCount: widget.dates.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final date = widget.dates[index];
          final isSelected =
              widget.selected != null &&
              date.year == widget.selected!.year &&
              date.month == widget.selected!.month &&
              date.day == widget.selected!.day;
          return _DateChip(
            date: date,
            isSelected: isSelected,
            onTap: () => widget.onSelect(date),
          );
        },
      ),
    );
  }
}

class _DateChip extends StatelessWidget {
  const _DateChip({
    required this.date,
    required this.isSelected,
    required this.onTap,
  });

  final DateTime date;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        width: 60,
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? colorScheme.primaryContainer
              : colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              DateFormat('M/d').format(date),
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: isSelected ? colorScheme.onPrimaryContainer : null,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              DateFormat('EEE', 'en_US').format(date).toUpperCase(),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: isSelected ? colorScheme.onPrimaryContainer : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
