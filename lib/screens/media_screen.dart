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

  List<DateTime> get _availableDates {
    final days =
        widget.videoLibrary.videos.map(_dayOf).toSet().toList()
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
      appBar: AppBar(title: const Text('メディア')),
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
                        return Dismissible(
                          key: ValueKey(video.file.path),
                          direction: DismissDirection.endToStart,
                          background: Container(
                            color: Colors.red,
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            child: const Icon(Icons.delete, color: Colors.white),
                          ),
                          onDismissed: (_) => widget.videoLibrary.delete(video),
                          child: ListTile(
                            leading: VideoThumbnail(file: video.file),
                            title: Text(DateFormat('HH:mm').format(video.createdAt)),
                            subtitle: Text(_formatDuration(video.duration)),
                            onTap: () {
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
                          ),
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
