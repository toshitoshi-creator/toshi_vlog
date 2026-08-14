import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../models/saved_sound.dart';
import '../models/sound_library.dart';
import '../models/video_item.dart';
import '../models/video_library.dart';
import '../widgets/video_thumbnail.dart';

/// Result of [SoundLibraryScreen]: either a chosen [sound] (BGM selected),
/// or [cleared] to explicitly turn BGM off. Distinct from popping the
/// screen with no result (back gesture), which callers should treat as "no
/// change" rather than "clear BGM".
class SoundSelection {
  const SoundSelection.sound(this.sound) : cleared = false;
  const SoundSelection.cleared() : sound = null, cleared = true;

  final SavedSound? sound;
  final bool cleared;
}

/// Lets the user pick a saved sound (or "no BGM") to use for the highlight
/// reel, and manage the sound library: extracting audio either from a video
/// picked from the camera roll or from one already recorded in the app.
///
/// Pops with a [SoundSelection] when the user makes a choice, or with no
/// result at all if dismissed via back gesture (see [SoundSelection]).
class SoundLibraryScreen extends StatefulWidget {
  const SoundLibraryScreen({
    super.key,
    required this.soundLibrary,
    required this.videoLibrary,
  });

  final SoundLibrary soundLibrary;
  final VideoLibrary videoLibrary;

  @override
  State<SoundLibraryScreen> createState() => _SoundLibraryScreenState();
}

class _SoundLibraryScreenState extends State<SoundLibraryScreen> {
  @override
  void initState() {
    super.initState();
    widget.soundLibrary.addListener(_onChanged);
  }

  @override
  void dispose() {
    widget.soundLibrary.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _addFromGallery() async {
    final picker = ImagePicker();
    final picked = await picker.pickVideo(source: ImageSource.gallery);
    if (picked == null) return;
    await _extractWithTitlePrompt(
      File(picked.path),
      defaultTitle: 'カメラロールの動画',
    );
  }

  Future<void> _addFromAppVideos() async {
    final videos = widget.videoLibrary.videos;
    if (videos.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('アプリ内に動画がありません')));
      return;
    }
    final selected = await showModalBottomSheet<VideoItem>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: videos.length,
          itemBuilder: (context, index) {
            final video = videos[index];
            return ListTile(
              leading: VideoThumbnail(file: video.file),
              title: Text(
                DateFormat('yyyy/MM/dd HH:mm').format(video.createdAt),
              ),
              onTap: () => Navigator.of(context).pop(video),
            );
          },
        ),
      ),
    );
    if (selected == null) return;
    await _extractWithTitlePrompt(
      selected.file,
      defaultTitle: DateFormat('yyyy/MM/dd HH:mm').format(selected.createdAt),
    );
  }

  Future<void> _extractWithTitlePrompt(
    File file, {
    required String defaultTitle,
  }) async {
    final controller = TextEditingController(text: defaultTitle);
    final title = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('サウンド名'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('抽出'),
          ),
        ],
      ),
    );
    if (title == null || title.isEmpty) return;
    await widget.soundLibrary.extractFromVideo(file, title: title);
  }

  Future<void> _showAddSourceSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('カメラロールの動画から音声を抽出'),
              onTap: () {
                Navigator.of(context).pop();
                _addFromGallery();
              },
            ),
            ListTile(
              leading: const Icon(Icons.video_library_outlined),
              title: const Text('アプリ内の動画から音声を抽出'),
              onTap: () {
                Navigator.of(context).pop();
                _addFromAppVideos();
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final library = widget.soundLibrary;
    return Scaffold(
      appBar: AppBar(
        title: const Text('BGMを選ぶ'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: '動画から音声を抽出',
            onPressed: library.isProcessing ? null : _showAddSourceSheet,
          ),
        ],
      ),
      body: Column(
        children: [
          if (library.errorMessage != null)
            Container(
              width: double.infinity,
              color: Colors.red.shade100,
              padding: const EdgeInsets.all(12),
              child: Text(library.errorMessage!),
            ),
          if (library.isProcessing)
            const LinearProgressIndicator(minHeight: 3),
          ListTile(
            leading: const Icon(Icons.music_off),
            title: const Text('BGMなし'),
            onTap: () => Navigator.of(
              context,
            ).pop<SoundSelection>(const SoundSelection.cleared()),
          ),
          const Divider(height: 1),
          Expanded(
            child: library.sounds.isEmpty
                ? const Center(child: Text('右上の + から動画の音声を取り込めます'))
                : ListView.builder(
                    itemCount: library.sounds.length,
                    itemBuilder: (context, index) {
                      final sound = library.sounds[index];
                      return ListTile(
                        leading: const Icon(Icons.music_note),
                        title: Text(sound.title),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => library.delete(sound),
                        ),
                        onTap: () => Navigator.of(
                          context,
                        ).pop<SoundSelection>(SoundSelection.sound(sound)),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
