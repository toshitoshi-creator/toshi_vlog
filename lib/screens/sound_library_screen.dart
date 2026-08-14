import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../models/bundled_track.dart';
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
  final _previewPlayer = AudioPlayer();
  String? _previewingTrackId;

  @override
  void initState() {
    super.initState();
    widget.soundLibrary.addListener(_onChanged);
    _previewPlayer.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _previewingTrackId = null);
    });
  }

  @override
  void dispose() {
    widget.soundLibrary.removeListener(_onChanged);
    _previewPlayer.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _togglePreview(BundledTrack track) async {
    if (_previewingTrackId == track.id) {
      await _previewPlayer.stop();
      setState(() => _previewingTrackId = null);
      return;
    }
    setState(() => _previewingTrackId = track.id);
    await _previewPlayer.play(AssetSource(track.previewAssetPath));
  }

  Future<void> _selectBundledTrack(BundledTrack track) async {
    await _previewPlayer.stop();
    final file = await track.materialize();
    if (!mounted) return;
    Navigator.of(context).pop<SoundSelection>(
      SoundSelection.sound(
        SavedSound(
          id: 'bundled_${track.id}',
          file: file,
          title: track.title,
          createdAt: DateTime.now(),
        ),
      ),
    );
  }

  Future<void> _addFromFilePicker() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.audio);
    final path = result?.files.single.path;
    if (path == null) return;
    final fileName = result!.files.single.name;
    final defaultTitle = fileName.contains('.')
        ? fileName.substring(0, fileName.lastIndexOf('.'))
        : fileName;
    await _extractWithTitlePrompt(
      File(path),
      defaultTitle: defaultTitle,
      isAlreadyAudio: true,
    );
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
    bool isAlreadyAudio = false,
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
            child: Text(isAlreadyAudio ? '追加' : '抽出'),
          ),
        ],
      ),
    );
    if (title == null || title.isEmpty) return;
    if (isAlreadyAudio) {
      await widget.soundLibrary.addFromFile(file, title: title);
    } else {
      await widget.soundLibrary.extractFromVideo(file, title: title);
    }
  }

  Future<void> _showAddSourceSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.audio_file_outlined),
              title: const Text('ファイルから選択'),
              onTap: () {
                Navigator.of(context).pop();
                _addFromFilePicker();
              },
            ),
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
            tooltip: '音声を追加',
            onPressed: library.isProcessing ? null : _showAddSourceSheet,
          ),
        ],
      ),
      body: ListView(
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
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              'フリー音源(商用利用可・著作権フリー)',
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ),
          for (final track in BundledTrack.all)
            ListTile(
              leading: IconButton(
                icon: Icon(
                  _previewingTrackId == track.id
                      ? Icons.stop_circle_outlined
                      : Icons.play_circle_outline,
                ),
                onPressed: () => _togglePreview(track),
              ),
              title: Text(track.title),
              onTap: () => _selectBundledTrack(track),
            ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text('マイサウンド', style: Theme.of(context).textTheme.labelLarge),
          ),
          if (library.sounds.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Text('右上の + からファイルや動画の音声を取り込めます'),
            )
          else
            for (final sound in library.sounds)
              ListTile(
                leading: const Icon(Icons.music_note),
                title: Text(sound.title),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => library.delete(sound),
                ),
                onTap: () => Navigator.of(
                  context,
                ).pop<SoundSelection>(SoundSelection.sound(sound)),
              ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
