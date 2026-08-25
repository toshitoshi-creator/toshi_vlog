import 'package:flutter/material.dart';

import '../models/app_font.dart';
import '../models/compilation_library.dart';
import '../models/download_quota.dart';
import '../models/highlight_reel.dart';
import '../models/redo_quota.dart';
import '../models/rewarded_ad_service.dart';
import '../models/sound_library.dart';
import '../models/subscription_service.dart';
import '../models/text_overlay.dart';
import '../models/video_library.dart';
import '../utils/text_overlay_renderer.dart';
import '../widgets/clip_management_section.dart';
import '../widgets/compiled_preview_section.dart';
import '../widgets/text_overlay_form_sheet.dart';
import 'paywall_screen.dart';
import 'sound_library_screen.dart';

class HighlightScreen extends StatefulWidget {
  const HighlightScreen({
    super.key,
    required this.compilationLibrary,
    required this.subscriptionService,
    required this.downloadQuota,
    required this.redoQuota,
    required this.rewardedAdService,
    required this.soundLibrary,
    required this.videoLibrary,
  });

  final CompilationLibrary compilationLibrary;
  final SubscriptionService subscriptionService;
  final DownloadQuota downloadQuota;
  final RedoQuota redoQuota;
  final RewardedAdService rewardedAdService;
  final SoundLibrary soundLibrary;
  final VideoLibrary videoLibrary;

  @override
  State<HighlightScreen> createState() => _HighlightScreenState();
}

class _HighlightScreenState extends State<HighlightScreen> {
  @override
  void initState() {
    super.initState();
    widget.compilationLibrary.current.addListener(_onChanged);
    widget.downloadQuota.addListener(_onChanged);
    widget.subscriptionService.addListener(_onChanged);
  }

  @override
  void dispose() {
    widget.compilationLibrary.current.removeListener(_onChanged);
    widget.downloadQuota.removeListener(_onChanged);
    widget.subscriptionService.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _handleFormResult(TextOverlay overlay) async {
    final reel = widget.compilationLibrary.current;
    final rendered = await renderTextOverlay(overlay, reel);
    await reel.upsertTextOverlay(rendered);
  }

  Future<void> _addText() async {
    final reel = widget.compilationLibrary.current;
    if (reel.segments.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('先にクリップを追加してください')));
      return;
    }
    final starts = reel.segmentStartTimes();
    final totalSeconds = starts.last.inMilliseconds / 1000;
    final result = await showModalBottomSheet<TextOverlay>(
      context: context,
      isScrollControlled: true,
      builder: (context) => TextOverlayFormSheet(
        initial: TextOverlay(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          text: '',
          fontId: AppFont.all.first.id,
          fontSize: 64,
          color: Colors.white,
          x: 0.5,
          y: 0.5,
          rotationDegrees: 0,
          startSeconds: 0,
          endSeconds: totalSeconds,
        ),
        totalSeconds: totalSeconds,
        clipBoundarySeconds: [for (final s in starts) s.inMilliseconds / 1000],
        showClipPicker: true,
      ),
    );
    if (result == null || result.text.trim().isEmpty) return;
    await _handleFormResult(result);
  }

  Future<void> _editText(TextOverlay overlay) async {
    final reel = widget.compilationLibrary.current;
    if (reel.segments.isEmpty) return;
    final starts = reel.segmentStartTimes();
    final totalSeconds = starts.last.inMilliseconds / 1000;
    final result = await showModalBottomSheet<TextOverlay>(
      context: context,
      isScrollControlled: true,
      builder: (context) => TextOverlayFormSheet(
        initial: overlay,
        totalSeconds: totalSeconds,
        clipBoundarySeconds: [for (final s in starts) s.inMilliseconds / 1000],
        showClipPicker: true,
        onDelete: () => reel.removeTextOverlay(overlay.id),
      ),
    );
    if (result == null) return;
    await _handleFormResult(result);
  }

  /// Just picking a track and adjusting its volume — no multi-track
  /// timeline editing here, that's the 編集 tab's job.
  Future<void> _handlePickBgm() async {
    final result = await Navigator.of(context).push<SoundSelection>(
      MaterialPageRoute(
        builder: (_) => SoundLibraryScreen(
          soundLibrary: widget.soundLibrary,
          videoLibrary: widget.videoLibrary,
        ),
      ),
    );
    if (result == null) return;
    await widget.compilationLibrary.current.setBgm(result.sound);
  }

  /// Overwrites the 編集 tab's independent project with a fresh copy of
  /// this one. One-directional by design — there's no equivalent button
  /// on the 編集 tab side to copy back.
  Future<void> _copyToEditTab() async {
    final reel = widget.compilationLibrary.current;
    if (reel.segments.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('先にクリップを追加してください')));
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('編集タブにコピーしますか?'),
        content: const Text(
          '簡易編集の内容(動画・コメントなど)を編集タブにコピーします。'
          '編集タブの現在の内容は上書きされます。この操作は取り消せません。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('コピー'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await reel.cloneInto(widget.compilationLibrary.currentEdit);
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('編集タブにコピーしました')));
  }

  Future<void> _handleOpenAutoClearSettings() async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (_) => _AutoClearSettingsSheet(
        reel: widget.compilationLibrary.current,
        subscriptionService: widget.subscriptionService,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final reel = widget.compilationLibrary.current;
    return Scaffold(
      appBar: AppBar(
        title: const Text('簡易編集'),
        actions: [
          IconButton(
            icon: Icon(
              reel.bgmFile != null ? Icons.music_note : Icons.music_off,
            ),
            tooltip: reel.bgmTitle ?? 'BGMを選ぶ',
            onPressed: _handlePickBgm,
          ),
          IconButton(
            icon: const Icon(Icons.auto_delete_outlined),
            tooltip: '自動削除設定',
            onPressed: _handleOpenAutoClearSettings,
          ),
          IconButton(
            icon: const Icon(Icons.arrow_circle_right_outlined),
            tooltip: '編集タブにコピー',
            onPressed: _copyToEditTab,
          ),
        ],
      ),
      body: ListView(
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
            child: CompiledPreviewSection(
              reel: reel,
              subscriptionService: widget.subscriptionService,
              downloadQuota: widget.downloadQuota,
              rewardedAdService: widget.rewardedAdService,
            ),
          ),
          const Divider(height: 1),
          ClipManagementSection(
            reel: reel,
            subscriptionService: widget.subscriptionService,
            redoQuota: widget.redoQuota,
          ),
          const Divider(height: 1),
          if (reel.bgmFile != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Row(
                children: [
                  const Icon(Icons.music_note, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      reel.bgmTitle ?? 'BGM',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: 'BGMを解除',
                    onPressed: () => reel.setBgm(null),
                  ),
                ],
              ),
            ),
          if (reel.bgmFile != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(
                children: [
                  const Icon(Icons.volume_up, size: 20),
                  Expanded(
                    child: Slider(
                      value: reel.bgmVolume.clamp(0, 1),
                      onChanged: (v) => reel.setVolumes(bgmVolume: v),
                    ),
                  ),
                ],
              ),
            ),
          if (reel.bgmFile != null) const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('テキスト', style: Theme.of(context).textTheme.labelLarge),
                FilledButton.tonalIcon(
                  onPressed: _addText,
                  icon: const Icon(Icons.add),
                  label: const Text('追加'),
                ),
              ],
            ),
          ),
          if (reel.textOverlays.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Text('まだテキストがありません'),
            )
          else
            for (final overlay in reel.textOverlays)
              ListTile(
                leading: Icon(Icons.text_fields, color: overlay.color),
                title: Text(overlay.text),
                subtitle: Text(
                  '${AppFont.byId(overlay.fontId).displayName} / '
                  '${formatSeconds(overlay.startSeconds)}〜'
                  '${formatSeconds(overlay.endSeconds)}',
                ),
                onTap: () => _editText(overlay),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => reel.removeTextOverlay(overlay.id),
                ),
              ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

/// Bottom sheet for the AppBar's 自動削除設定 icon: explains 簡易編集's
/// "starts fresh after a day" policy and, for premium users, lets it be
/// turned off. Free users see the switch permanently on and locked —
/// tapping it opens the paywall instead of actually toggling anything,
/// same pattern as the export-resolution/fps gating in
/// ExportSettingsSheet.
class _AutoClearSettingsSheet extends StatefulWidget {
  const _AutoClearSettingsSheet({
    required this.reel,
    required this.subscriptionService,
  });

  final HighlightReel reel;
  final SubscriptionService subscriptionService;

  @override
  State<_AutoClearSettingsSheet> createState() =>
      _AutoClearSettingsSheetState();
}

class _AutoClearSettingsSheetState extends State<_AutoClearSettingsSheet> {
  Future<void> _openPaywall() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            PaywallScreen(subscriptionService: widget.subscriptionService),
      ),
    );
  }

  Future<void> _setEnabled(bool value) async {
    if (!widget.subscriptionService.isPremium) {
      await _openPaywall();
      return;
    }
    await widget.reel.setAutoClearEnabled(value);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final isPremium = widget.subscriptionService.isPremium;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('自動削除設定', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              '簡易編集は作成から1日経つと、クリップ・コメント・BGMが自動的に'
              'リセットされます。プレミアム登録すると、この自動削除をオフに'
              'できます。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('1日で自動削除する'),
              secondary: isPremium ? null : const Icon(Icons.lock, size: 18),
              value: !isPremium || widget.reel.autoClearEnabled,
              onChanged: _setEnabled,
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('閉じる'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
