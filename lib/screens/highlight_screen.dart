import 'package:flutter/material.dart';

import '../models/clip_trim_mode.dart';
import '../models/highlight_reel.dart';
import '../widgets/video_thumbnail.dart';
import 'video_player_screen.dart';

class HighlightScreen extends StatefulWidget {
  const HighlightScreen({super.key, required this.highlightReel});

  final HighlightReel highlightReel;

  @override
  State<HighlightScreen> createState() => _HighlightScreenState();
}

class _HighlightScreenState extends State<HighlightScreen> {
  @override
  void initState() {
    super.initState();
    widget.highlightReel.addListener(_onChanged);
  }

  @override
  void dispose() {
    widget.highlightReel.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final reel = widget.highlightReel;
    return Scaffold(
      appBar: AppBar(title: const Text('まとめ動画')),
      body: Column(
        children: [
          if (reel.errorMessage != null)
            Container(
              width: double.infinity,
              color: Colors.red.shade100,
              padding: const EdgeInsets.all(12),
              child: Text(reel.errorMessage!),
            ),
          if (reel.isProcessing) const LinearProgressIndicator(minHeight: 3),
          Padding(
            padding: const EdgeInsets.all(16),
            child: _CompiledPreview(reel: reel),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('切り出し方法', style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 8),
                SegmentedButton<ClipTrimMode>(
                  segments: [
                    for (final mode in ClipTrimMode.values)
                      ButtonSegment(value: mode, label: Text(mode.label)),
                  ],
                  selected: {reel.trimMode},
                  onSelectionChanged: (selection) =>
                      reel.setTrimMode(selection.first),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '撮影した動画から選んだ方式で1秒だけ切り取られ、ここに追加されます'
                '(切り替えは以降撮影分から適用されます)。並び替えや削除で手動編集できます。',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ),
          Expanded(
            child: reel.segments.isEmpty
                ? const Center(child: Text('まだクリップがありません'))
                : ReorderableListView.builder(
                    itemCount: reel.segments.length,
                    onReorderItem: (oldIndex, newIndex) {
                      reel.reorder(oldIndex, newIndex);
                    },
                    itemBuilder: (context, index) {
                      final segment = reel.segments[index];
                      return ListTile(
                        key: ValueKey(segment.id),
                        leading: VideoThumbnail(file: segment.file),
                        title: Text('${index + 1}番目'),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => reel.removeAt(index),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _CompiledPreview extends StatelessWidget {
  const _CompiledPreview({required this.reel});

  final HighlightReel reel;

  @override
  Widget build(BuildContext context) {
    final file = reel.compiledFile;
    if (file == null) {
      return const Text('まだまとめ動画がありません');
    }
    return FilledButton.icon(
      onPressed: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => VideoPlayerScreen(file: file, title: 'まとめ動画'),
          ),
        );
      },
      icon: const Icon(Icons.play_arrow),
      label: Text('まとめ動画を再生 (${reel.segments.length}秒)'),
    );
  }
}
