import 'package:flutter/material.dart';

import '../models/app_font.dart';
import '../models/compilation_library.dart';
import '../models/download_quota.dart';
import '../models/subscription_service.dart';
import '../models/text_overlay.dart';
import '../utils/text_overlay_renderer.dart';
import '../widgets/clip_management_section.dart';
import '../widgets/compiled_preview_section.dart';
import '../widgets/text_overlay_form_sheet.dart';

class HighlightScreen extends StatefulWidget {
  const HighlightScreen({
    super.key,
    required this.compilationLibrary,
    required this.subscriptionService,
    required this.downloadQuota,
  });

  final CompilationLibrary compilationLibrary;
  final SubscriptionService subscriptionService;
  final DownloadQuota downloadQuota;

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

  @override
  Widget build(BuildContext context) {
    final reel = widget.compilationLibrary.current;
    return Scaffold(
      appBar: AppBar(title: const Text('まとめ動画')),
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
            ),
          ),
          const Divider(height: 1),
          ClipManagementSection(
            reel: reel,
            subscriptionService: widget.subscriptionService,
          ),
          const Divider(height: 1),
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
