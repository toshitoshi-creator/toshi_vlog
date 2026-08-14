import 'dart:io';

import 'package:flutter/material.dart';
import 'package:gal/gal.dart';

import '../models/clip_trim_mode.dart';
import '../models/download_quota.dart';
import '../models/highlight_reel.dart';
import '../models/subscription_service.dart';
import '../widgets/video_thumbnail.dart';
import 'paywall_screen.dart';
import 'video_player_screen.dart';

class HighlightScreen extends StatefulWidget {
  const HighlightScreen({
    super.key,
    required this.highlightReel,
    required this.subscriptionService,
    required this.downloadQuota,
  });

  final HighlightReel highlightReel;
  final SubscriptionService subscriptionService;
  final DownloadQuota downloadQuota;

  @override
  State<HighlightScreen> createState() => _HighlightScreenState();
}

class _HighlightScreenState extends State<HighlightScreen> {
  bool _isDownloading = false;

  @override
  void initState() {
    super.initState();
    widget.highlightReel.addListener(_onChanged);
    widget.downloadQuota.addListener(_onChanged);
    widget.subscriptionService.addListener(_onChanged);
  }

  @override
  void dispose() {
    widget.highlightReel.removeListener(_onChanged);
    widget.downloadQuota.removeListener(_onChanged);
    widget.subscriptionService.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  void _handleRedo(int index) {
    if (!widget.subscriptionService.isPremium) {
      _openPaywall();
      return;
    }
    widget.highlightReel.redo(index);
  }

  void _openPaywall() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            PaywallScreen(subscriptionService: widget.subscriptionService),
      ),
    );
  }

  Future<void> _handleDownload(File file) async {
    final subscription = widget.subscriptionService;
    final quota = widget.downloadQuota;
    final canDownload =
        subscription.isPremium || quota.remainingFreeDownloads > 0;
    if (!canDownload) {
      _openPaywall();
      return;
    }

    setState(() => _isDownloading = true);
    try {
      var hasAccess = await Gal.hasAccess();
      if (!hasAccess) {
        hasAccess = await Gal.requestAccess();
      }
      if (!hasAccess) {
        _showSnackBar('写真ライブラリへのアクセスが許可されていません');
        return;
      }
      await Gal.putVideo(file.path, album: 'ToshiVlog');
      if (!subscription.isPremium) {
        await quota.recordDownload();
      }
      _showSnackBar('カメラロールに保存しました');
    } catch (_) {
      _showSnackBar('保存に失敗しました');
    } finally {
      if (mounted) setState(() => _isDownloading = false);
    }
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final reel = widget.highlightReel;
    final subscription = widget.subscriptionService;
    final quota = widget.downloadQuota;
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
            child: _CompiledPreview(
              reel: reel,
              isDownloading: _isDownloading,
              downloadLabel: subscription.isPremium
                  ? 'ダウンロード (プレミアム: 無制限)'
                  : 'ダウンロード (本日あと${quota.remainingFreeDownloads}回)',
              onDownload: _handleDownload,
            ),
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
                const SizedBox(height: 16),
                Text('クリップの長さ', style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 8),
                SegmentedButton<Duration>(
                  segments: const [
                    ButtonSegment(
                      value: Duration(seconds: 1),
                      label: Text('1秒'),
                    ),
                    ButtonSegment(
                      value: Duration(seconds: 2),
                      label: Text('2秒'),
                    ),
                    ButtonSegment(
                      value: Duration(seconds: 3),
                      label: Text('3秒'),
                    ),
                  ],
                  selected: {reel.clipDuration},
                  onSelectionChanged: (selection) =>
                      reel.setClipDuration(selection.first),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '撮影した動画から選んだ方式・長さで切り取られ、ここに追加されます'
                '(切り替えは以降撮影分から適用されます)。並び替えや削除で手動編集できます。'
                'ランダム・盛り上がりのクリップの作り直しと、1日4回目以降のダウンロードは'
                'プレミアム登録で解除されます。',
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
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (reel.trimMode != ClipTrimMode.start)
                              IconButton(
                                icon: const Icon(Icons.refresh),
                                tooltip: '作り直す',
                                onPressed: () => _handleRedo(index),
                              ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () => reel.removeAt(index),
                            ),
                          ],
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
  const _CompiledPreview({
    required this.reel,
    required this.isDownloading,
    required this.downloadLabel,
    required this.onDownload,
  });

  final HighlightReel reel;
  final bool isDownloading;
  final String downloadLabel;
  final ValueChanged<File> onDownload;

  @override
  Widget build(BuildContext context) {
    final file = reel.compiledFile;
    if (file == null) {
      return const Text('まだまとめ動画がありません');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.icon(
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => VideoPlayerScreen(file: file, title: 'まとめ動画'),
              ),
            );
          },
          icon: const Icon(Icons.play_arrow),
          label: Text('まとめ動画を再生 (${reel.segments.length}クリップ)'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: isDownloading ? null : () => onDownload(file),
          icon: isDownloading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.download),
          label: Text(downloadLabel),
        ),
      ],
    );
  }
}
