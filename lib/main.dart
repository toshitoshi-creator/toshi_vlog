import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'models/download_quota.dart';
import 'models/highlight_reel.dart';
import 'models/sound_library.dart';
import 'models/subscription_service.dart';
import 'models/video_library.dart';
import 'screens/camera_screen.dart';
import 'screens/edit_screen.dart';
import 'screens/highlight_screen.dart';
import 'screens/media_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting();
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
  final SubscriptionService _subscriptionService = SubscriptionService();
  final DownloadQuota _downloadQuota = DownloadQuota();
  final SoundLibrary _soundLibrary = SoundLibrary();
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _highlightReel.load();
    _subscriptionService.init();
    _downloadQuota.load();
    _soundLibrary.load();
  }

  @override
  void dispose() {
    _videoLibrary.dispose();
    _highlightReel.dispose();
    _subscriptionService.dispose();
    _downloadQuota.dispose();
    _soundLibrary.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screens = [
      CameraScreen(videoLibrary: _videoLibrary, highlightReel: _highlightReel),
      HighlightScreen(
        highlightReel: _highlightReel,
        subscriptionService: _subscriptionService,
        downloadQuota: _downloadQuota,
      ),
      EditScreen(
        highlightReel: _highlightReel,
        soundLibrary: _soundLibrary,
        videoLibrary: _videoLibrary,
      ),
      MediaScreen(videoLibrary: _videoLibrary),
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
          NavigationDestination(icon: Icon(Icons.edit), label: '編集'),
          NavigationDestination(icon: Icon(Icons.photo_library), label: 'メディア'),
        ],
      ),
    );
  }
}
