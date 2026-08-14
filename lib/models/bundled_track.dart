import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';

/// A free, app-bundled BGM track (public domain / CC0 — see
/// `assets/music/NOTICE.md`). [assetPath] is the Flutter asset; since ffmpeg
/// needs a real filesystem path to mux it into the compiled video,
/// [materialize] copies it out of the asset bundle into the app's documents
/// directory the first time it's selected.
class BundledTrack {
  const BundledTrack({required this.id, required this.title});

  final String id;
  final String title;

  String get assetPath => 'assets/music/$id.mp3';

  /// Path relative to the assets root, as expected by audioplayers'
  /// `AssetSource` (which applies its own `assets/` prefix).
  String get previewAssetPath => 'music/$id.mp3';

  Future<File> materialize() async {
    final documentsDir = await getApplicationDocumentsDirectory();
    final dir = Directory('${documentsDir.path}/bundled_music');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final file = File('${dir.path}/$id.mp3');
    if (!await file.exists()) {
      final data = await rootBundle.load(assetPath);
      await file.writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      );
    }
    return file;
  }

  static const all = <BundledTrack>[
    BundledTrack(id: 'lovely_piano_song', title: 'やさしいピアノ'),
    BundledTrack(id: 'nostalgic_piano', title: 'ノスタルジックピアノ'),
    BundledTrack(id: 'celebrated_minuet', title: '上品なメヌエット(ピアノ)'),
    BundledTrack(id: 'happy_whistling_ukulele', title: '陽気なウクレレ'),
    BundledTrack(id: 'ukulele_song', title: 'ウクレレのうた'),
    BundledTrack(id: 'lukewarm_banjo', title: 'ゆったりバンジョー'),
    BundledTrack(id: 'kalimba_relaxation', title: '癒やしのカリンバ'),
    BundledTrack(id: 'still_pickin', title: 'アコースティックギター弾き語り'),
    BundledTrack(id: 'windy_old_weather', title: '風薫るフォークギター'),
    BundledTrack(id: 'river_meditation', title: '静かな瞑想ピアノ'),
  ];
}
