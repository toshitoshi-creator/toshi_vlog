import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'models/compilation_library.dart';
import 'models/download_quota.dart';
import 'models/redo_quota.dart';
import 'models/rewarded_ad_service.dart';
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
  final CompilationLibrary _compilationLibrary = CompilationLibrary();
  final SubscriptionService _subscriptionService = SubscriptionService();
  final DownloadQuota _downloadQuota = DownloadQuota();
  final RedoQuota _redoQuota = RedoQuota();
  final RewardedAdService _rewardedAdService = RewardedAdService();
  final SoundLibrary _soundLibrary = SoundLibrary();
  int _currentIndex = 0;

  /// In landscape the bottom NavigationBar eats into the already-short
  /// vertical space, so it starts collapsed there and can be expanded via
  /// the floating toggle button. Always shown (uncollapsible) in portrait.
  bool _showNavInLandscape = false;

  @override
  void initState() {
    super.initState();
    _initCompilationAndSubscription();
    _downloadQuota.load();
    _redoQuota.load();
    _rewardedAdService.init();
    _soundLibrary.load();
  }

  /// 簡易編集's daily auto-clear (see [HighlightReel.applyDailyAutoClear])
  /// needs both the reel's own clips and the subscription state loaded
  /// first, so these two run together before it's applied — unlike the
  /// other independent loads above, which don't depend on each other.
  Future<void> _initCompilationAndSubscription() async {
    await Future.wait([
      _compilationLibrary.load(),
      _subscriptionService.init(),
    ]);
    await _compilationLibrary.current.applyDailyAutoClear(
      isPremium: _subscriptionService.isPremium,
    );
  }

  @override
  void dispose() {
    _videoLibrary.dispose();
    _compilationLibrary.dispose();
    _subscriptionService.dispose();
    _downloadQuota.dispose();
    _redoQuota.dispose();
    _rewardedAdService.dispose();
    _soundLibrary.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screens = [
      CameraScreen(
        videoLibrary: _videoLibrary,
        highlightReel: _compilationLibrary.current,
      ),
      HighlightScreen(
        compilationLibrary: _compilationLibrary,
        subscriptionService: _subscriptionService,
        downloadQuota: _downloadQuota,
        redoQuota: _redoQuota,
        rewardedAdService: _rewardedAdService,
        soundLibrary: _soundLibrary,
        videoLibrary: _videoLibrary,
      ),
      EditScreen(
        compilationLibrary: _compilationLibrary,
        soundLibrary: _soundLibrary,
        videoLibrary: _videoLibrary,
        subscriptionService: _subscriptionService,
        downloadQuota: _downloadQuota,
        rewardedAdService: _rewardedAdService,
      ),
      MediaScreen(videoLibrary: _videoLibrary),
    ];

    final isLandscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    final showNavBar = !isLandscape || _showNavInLandscape;

    return Scaffold(
      body: Stack(
        children: [
          IndexedStack(index: _currentIndex, children: screens),
          if (isLandscape)
            Positioned(
              right: 8,
              bottom: 8,
              child: SafeArea(
                child: FloatingActionButton.small(
                  heroTag: 'nav-toggle',
                  tooltip: showNavBar ? 'タブを隠す' : 'タブを表示',
                  onPressed: () => setState(
                    () => _showNavInLandscape = !_showNavInLandscape,
                  ),
                  child: Icon(showNavBar ? Icons.expand_more : Icons.apps),
                ),
              ),
            ),
        ],
      ),
      bottomNavigationBar: showNavBar
          ? NavigationBar(
              selectedIndex: _currentIndex,
              onDestinationSelected: (index) {
                setState(() {
                  _currentIndex = index;
                  if (isLandscape) _showNavInLandscape = false;
                });
              },
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.camera_alt),
                  label: 'カメラ',
                ),
                NavigationDestination(
                  icon: Icon(Icons.movie_creation_outlined),
                  label: '簡易編集',
                ),
                NavigationDestination(icon: Icon(Icons.edit), label: '編集'),
                NavigationDestination(
                  icon: Icon(Icons.photo_library),
                  label: 'メディア',
                ),
              ],
            )
          : null,
    );
  }
}
