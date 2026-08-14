import 'package:flutter/material.dart';

import '../models/compilation_library.dart';
import '../models/download_quota.dart';
import '../models/subscription_service.dart';
import '../widgets/clip_management_section.dart';
import '../widgets/compiled_preview_section.dart';

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
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
