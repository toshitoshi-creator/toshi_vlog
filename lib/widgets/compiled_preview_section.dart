import 'dart:io';

import 'package:flutter/material.dart';
import 'package:gal/gal.dart';

import '../models/download_quota.dart';
import '../models/highlight_reel.dart';
import '../models/subscription_service.dart';
import '../screens/paywall_screen.dart';
import '../screens/video_player_screen.dart';

/// Compiled-video preview (play button) and camera-roll download button for
/// [reel], gated by [subscriptionService]/[downloadQuota]'s free-download
/// quota. Shared by the まとめ and 編集 tabs so both operate on whichever
/// compilation is currently in view.
class CompiledPreviewSection extends StatefulWidget {
  const CompiledPreviewSection({
    super.key,
    required this.reel,
    required this.subscriptionService,
    required this.downloadQuota,
    this.onPlayInline,
  });

  final HighlightReel reel;
  final SubscriptionService subscriptionService;
  final DownloadQuota downloadQuota;

  /// When set, the play button triggers this instead of opening a
  /// full-screen player — used by the 編集 tab, which already has its own
  /// inline video preview to play from.
  final VoidCallback? onPlayInline;

  @override
  State<CompiledPreviewSection> createState() =>
      _CompiledPreviewSectionState();
}

class _CompiledPreviewSectionState extends State<CompiledPreviewSection> {
  bool _isDownloading = false;

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
