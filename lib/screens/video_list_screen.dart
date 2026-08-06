import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/video_library.dart';
import '../widgets/video_thumbnail.dart';
import 'video_player_screen.dart';

class VideoListScreen extends StatefulWidget {
  const VideoListScreen({super.key, required this.videoLibrary});

  final VideoLibrary videoLibrary;

  @override
  State<VideoListScreen> createState() => _VideoListScreenState();
}

class _VideoListScreenState extends State<VideoListScreen> {
  @override
  void initState() {
    super.initState();
    widget.videoLibrary.addListener(_onLibraryChanged);
    widget.videoLibrary.reload();
  }

  @override
  void dispose() {
    widget.videoLibrary.removeListener(_onLibraryChanged);
    super.dispose();
  }

  void _onLibraryChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final videos = widget.videoLibrary.videos;
    return Scaffold(
      appBar: AppBar(title: const Text('撮影した動画')),
      body: RefreshIndicator(
        onRefresh: widget.videoLibrary.reload,
        child: videos.isEmpty
            ? ListView(
                children: const [
                  SizedBox(height: 120),
                  Icon(Icons.videocam_off, size: 48, color: Colors.grey),
                  SizedBox(height: 16),
                  Center(child: Text('動画がありません')),
                  SizedBox(height: 8),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 32),
                    child: Text(
                      'カメラタブで撮影すると、ここに一覧表示されます',
                      style: TextStyle(color: Colors.grey),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              )
            : ListView.builder(
                itemCount: videos.length,
                itemBuilder: (context, index) {
                  final video = videos[index];
                  return Dismissible(
                    key: ValueKey(video.file.path),
                    direction: DismissDirection.endToStart,
                    background: Container(
                      color: Colors.red,
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: const Icon(Icons.delete, color: Colors.white),
                    ),
                    onDismissed: (_) => widget.videoLibrary.delete(video),
                    child: ListTile(
                      leading: VideoThumbnail(video: video),
                      title: Text(
                        DateFormat('yyyy/MM/dd HH:mm').format(video.createdAt),
                      ),
                      subtitle: Text(_formatDuration(video.duration)),
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => VideoPlayerScreen(video: video),
                          ),
                        );
                      },
                    ),
                  );
                },
              ),
      ),
    );
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}
