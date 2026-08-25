import 'dart:io';

import 'package:flutter/material.dart';

import '../models/download_quota.dart';
import '../models/highlight_reel.dart';
import '../models/rewarded_ad_service.dart';
import '../models/subscription_service.dart';
import '../screens/paywall_screen.dart';
import '../screens/video_player_screen.dart';
import '../utils/download_video.dart';

/// What a non-premium user picked from [_CompiledPreviewSectionState._showQuotaExhaustedSheet]
/// once today's free downloads are used up.
enum _DownloadChoice { premium, watchAd }

/// Compiled-video preview (play button) and camera-roll download button for
/// [reel], gated by [subscriptionService]/[downloadQuota]'s free-download
/// quota. Used by the まとめ tab (簡易編集) — 編集 has its own download flow,
/// which additionally burns in a watermark for non-premium users.
class CompiledPreviewSection extends StatefulWidget {
  const CompiledPreviewSection({
    super.key,
    required this.reel,
    required this.subscriptionService,
    required this.downloadQuota,
    required this.rewardedAdService,
    this.onPlayInline,
  });

  final HighlightReel reel;
  final SubscriptionService subscriptionService;
  final DownloadQuota downloadQuota;
  final RewardedAdService rewardedAdService;

  /// When set, the play button triggers this instead of opening a
  /// full-screen player — used by the 編集 tab, which already has its own
  /// inline video preview to play from.
  final VoidCallback? onPlayInline;

  @override
  State<CompiledPreviewSection> createState() => _CompiledPreviewSectionState();
}

class _CompiledPreviewSectionState extends State<CompiledPreviewSection> {
  bool _isDownloading = false;

  Future<void> _handleDownload(File file) async {
    // Non-premium: confirm before spending a free download, or — once
    // today's free downloads are used up — offer premium or a rewarded ad
    // as a way to unlock one more, instead of going straight to the
    // paywall.
    var bypassQuota = false;
    if (!widget.subscriptionService.isPremium) {
      final remaining = widget.downloadQuota.remainingFreeDownloads;
      if (remaining > 0) {
        final confirmed = await _confirmFreeDownload(remaining);
        if (confirmed != true) return;
      } else {
        final choice = await _showQuotaExhaustedSheet();
        if (choice == null) return;
        if (choice == _DownloadChoice.premium) {
          if (!mounted) return;
          await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => PaywallScreen(
                subscriptionService: widget.subscriptionService,
              ),
            ),
          );
          return;
        }
        final earned = await widget.rewardedAdService.showAd();
        if (!mounted) return;
        if (!earned) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('広告を最後まで視聴すると1回ダウンロードできます')),
          );
          return;
        }
        bypassQuota = true;
      }
    }

    if (!mounted) return;
    setState(() => _isDownloading = true);
    await downloadCompiledVideo(
      context: context,
      file: file,
      subscriptionService: widget.subscriptionService,
      downloadQuota: widget.downloadQuota,
      bypassQuota: bypassQuota,
    );
    if (mounted) setState(() => _isDownloading = false);
  }

  Future<bool?> _confirmFreeDownload(int remaining) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ダウンロードしますか?'),
        content: Text('無料プランでは本日あと$remaining回ダウンロードできます。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('ダウンロード'),
          ),
        ],
      ),
    );
  }

  Future<_DownloadChoice?> _showQuotaExhaustedSheet() {
    return showModalBottomSheet<_DownloadChoice>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text('本日の無料ダウンロード回数を使い切りました'),
            ),
            ListTile(
              leading: const Icon(Icons.workspace_premium),
              title: const Text('プレミアムプランを見る'),
              onTap: () => Navigator.of(context).pop(_DownloadChoice.premium),
            ),
            ListTile(
              leading: const Icon(Icons.ondemand_video),
              title: const Text('広告を見てダウンロード'),
              onTap: () => Navigator.of(context).pop(_DownloadChoice.watchAd),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final reel = widget.reel;
    final subscription = widget.subscriptionService;
    final quota = widget.downloadQuota;
    final file = reel.compiledFile;
    if (file == null) {
      return const Text('まだまとめ動画がありません');
    }
    final downloadLabel = subscription.isPremium
        ? 'ダウンロード (プレミアム: 無制限)'
        : 'ダウンロード (本日あと${quota.remainingFreeDownloads}回)';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.icon(
          onPressed:
              widget.onPlayInline ??
              () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        VideoPlayerScreen(file: file, title: 'まとめ動画'),
                  ),
                );
              },
          icon: const Icon(Icons.play_arrow),
          label: Text('まとめ動画を再生 (${reel.segments.length}クリップ)'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _isDownloading ? null : () => _handleDownload(file),
          icon: _isDownloading
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
