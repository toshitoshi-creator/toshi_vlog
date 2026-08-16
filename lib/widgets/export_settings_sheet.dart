import 'package:flutter/material.dart';

import '../models/export_settings.dart';
import '../models/highlight_reel.dart';
import '../models/subscription_service.dart';
import '../screens/paywall_screen.dart';

/// 詳細設定 bottom sheet: export resolution/frame rate (4K and 60fps are
/// premium-only), the opening on/off toggle, and BGM/video volume sliders.
/// Every control writes straight through to [reel], which persists and
/// recomposes on each change — this sheet holds no state of its own beyond
/// what's needed for smooth slider dragging.
class ExportSettingsSheet extends StatefulWidget {
  const ExportSettingsSheet({
    super.key,
    required this.reel,
    required this.subscriptionService,
  });

  final HighlightReel reel;
  final SubscriptionService subscriptionService;

  @override
  State<ExportSettingsSheet> createState() => _ExportSettingsSheetState();
}

class _ExportSettingsSheetState extends State<ExportSettingsSheet> {
  late double _videoVolume;
  late double _bgmVolume;

  @override
  void initState() {
    super.initState();
    _videoVolume = widget.reel.videoVolume;
    _bgmVolume = widget.reel.bgmVolume;
  }

  Future<void> _openPaywall() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            PaywallScreen(subscriptionService: widget.subscriptionService),
      ),
    );
  }

  bool get _isPremium => widget.subscriptionService.isPremium;

  Future<void> _setResolution(ExportResolution resolution) async {
    if (resolution == ExportResolution.uhd && !_isPremium) {
      await _openPaywall();
      return;
    }
    await widget.reel.setExportSettings(resolution: resolution);
    if (mounted) setState(() {});
  }

  Future<void> _setFps(int fps) async {
    if (fps == 60 && !_isPremium) {
      await _openPaywall();
      return;
    }
    await widget.reel.setExportSettings(fps: fps);
    if (mounted) setState(() {});
  }

  Future<void> _setIncludeOpening(bool value) async {
    await widget.reel.setIncludeOpening(value);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final reel = widget.reel;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('詳細設定', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 16),
              Text('解像度', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 8),
              SegmentedButton<ExportResolution>(
                segments: [
                  const ButtonSegment(
                    value: ExportResolution.hd,
                    label: Text('HD'),
                  ),
                  ButtonSegment(
                    value: ExportResolution.uhd,
                    label: const Text('4K'),
                    icon: _isPremium ? null : const Icon(Icons.lock, size: 16),
                  ),
                ],
                selected: {reel.exportResolution},
                onSelectionChanged: (s) => _setResolution(s.first),
              ),
              const SizedBox(height: 16),
              Text('フレームレート', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 8),
              SegmentedButton<int>(
                segments: [
                  const ButtonSegment(value: 30, label: Text('30fps')),
                  ButtonSegment(
                    value: 60,
                    label: const Text('60fps'),
                    icon: _isPremium ? null : const Icon(Icons.lock, size: 16),
                  ),
                ],
                selected: {reel.exportFps},
                onSelectionChanged: (s) => _setFps(s.first),
              ),
              Text(
                '4K・60fpsの書き出しはサブスクのみご利用いただけます',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const Divider(height: 32),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('オープニング'),
                subtitle: Text(
                  reel.canIncludeOpening
                      ? '各クリップの中央1秒間をつなげて動画の先頭に追加します'
                      : 'クリップが${HighlightReel.minClipsForOpening}本以上になると設定できます'
                          '(現在${reel.segments.length}本)',
                ),
                value: reel.includeOpening,
                onChanged: reel.canIncludeOpening
                    ? (v) => _setIncludeOpening(v)
                    : null,
              ),
              const Divider(height: 32),
              Text('音量', style: Theme.of(context).textTheme.titleSmall),
              Row(
                children: [
                  const Text('動画の音量'),
                  const Spacer(),
                  Text('${(_videoVolume * 100).round()}%'),
                ],
              ),
              Slider(
                value: _videoVolume,
                min: 0,
                max: 2,
                divisions: 40,
                onChanged: (v) => setState(() => _videoVolume = v),
                onChangeEnd: (v) => reel.setVolumes(videoVolume: v),
              ),
              Row(
                children: [
                  const Text('BGMの音量'),
                  const Spacer(),
                  Text('${(_bgmVolume * 100).round()}%'),
                ],
              ),
              Slider(
                value: _bgmVolume,
                min: 0,
                max: 2,
                divisions: 40,
                onChanged: (v) => setState(() => _bgmVolume = v),
                onChangeEnd: (v) => reel.setVolumes(bgmVolume: v),
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
      ),
    );
  }
}
