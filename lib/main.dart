import 'package:flutter/material.dart';

import 'models/highlight_reel.dart';
import 'models/video_library.dart';
import 'screens/camera_screen.dart';
import 'screens/highlight_screen.dart';
import 'screens/video_list_screen.dart';

void main() {
  runApp(const ToshiVlogApp());
}

class ToshiVlogApp extends StatelessWidget {
  const ToshiVlogApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ToshiVlog',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const RootScreen(),
    );
  }
}

class RootScreen extends StatefulWidget {
  const RootScreen({super.key});

  @override
  State<RootScreen> createState() => _RootScreenState();
}

class _RootScreenState extends State<RootScreen> {
  final VideoLibrary _videoLibrary = VideoLibrary();
  final HighlightReel _highlightReel = HighlightReel();
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _highlightReel.load();
  }

  @override
  void dispose() {
    _videoLibrary.dispose();
    _highlightReel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screens = [
      CameraScreen(videoLibrary: _videoLibrary, highlightReel: _highlightReel),
      HighlightScreen(highlightReel: _highlightReel),
      VideoListScreen(videoLibrary: _videoLibrary),
    ];

    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: screens),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) => setState(() => _currentIndex = index),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.camera_alt), label: 'カメラ'),
          NavigationDestination(
            icon: Icon(Icons.movie_creation_outlined),
            label: 'まとめ',
          ),
          NavigationDestination(icon: Icon(Icons.list), label: '一覧'),
        ],
      ),
    );
  }
}
