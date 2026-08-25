import 'package:flutter/material.dart';

import '../models/clip_trim_mode.dart';
import '../models/download_quota.dart';
import '../models/highlight_reel.dart';
import '../models/redo_quota.dart';
import '../models/subscription_service.dart';
import '../screens/paywall_screen.dart';
import 'video_thumbnail.dart';

/// Trim-mode/clip-duration controls plus the reorderable clip list for
/// [reel]. Shared by the まとめ and 編集 tabs. Designed to be embedded inside
/// a scrollable parent (e.g. `ListView`) via its own shrink-wrapped list.
class ClipManagementSection extends StatelessWidget {
  const ClipManagementSection({
    super.key,
    required this.reel,
    required this.subscriptionService,
    required this.redoQuota,
  });

  final HighlightReel reel;
  final SubscriptionService subscriptionService;
  final RedoQuota redoQuota;

  void _openPaywall(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PaywallScreen(subscriptionService: subscriptionService),
      ),
    );
  }

  void _handleRedo(BuildContext context, int index) {
    final canRedo =
        subscriptionService.isPremium || redoQuota.remainingFreeRedos > 0;
    if (!canRedo) {
      _openPaywall(context);
      return;
    }
    reel.redo(index);
    if (!subscriptionService.isPremium) {
      redoQuota.recordRedo();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
                  ButtonSegment(value: Duration(seconds: 1), label: Text('1秒')),
                  ButtonSegment(value: Duration(seconds: 2), label: Text('2秒')),
                  ButtonSegment(value: Duration(seconds: 3), label: Text('3秒')),
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
          child: Text(
            '撮影した動画から選んだ方式・長さで切り取られ、ここに追加されます'
            '(切り替えは以降撮影分から適用されます)。並び替えや削除で手動編集できます。'
            'ランダム・盛り上がりのクリップの作り直しは1日${RedoQuota.freeRedosPerDay}回、'
            'ダウンロードは1日${DownloadQuota.freeDownloadsPerDay}回まで無料'
            '(それ以降はプレミアム登録で解除されます)。',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        if (reel.segments.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Text('まだクリップがありません'),
          )
        else
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: reel.segments.length,
            onReorderItem: (oldIndex, newIndex) {
              reel.reorder(oldIndex, newIndex);
            },
            itemBuilder: (context, index) {
              final segment = reel.segments[index];
              final durationLabel =
                  '${(segment.duration.inMilliseconds / 1000).toStringAsFixed(1)}秒';
              final modeLabel = segment.trimModeUsed?.label;
              return ListTile(
                key: ValueKey(segment.id),
                leading: VideoThumbnail(file: segment.file),
                title: Text('${index + 1}番目'),
                subtitle: Text(
                  modeLabel != null
                      ? '$modeLabel・$durationLabel'
                      : durationLabel,
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (reel.trimMode != ClipTrimMode.start)
                      IconButton(
                        icon: const Icon(Icons.refresh),
                        tooltip: '作り直す',
                        onPressed: () => _handleRedo(context, index),
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
      ],
    );
  }
}
