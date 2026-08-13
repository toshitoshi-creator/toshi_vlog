enum ClipTrimMode {
  start,
  loudest,
  random;

  String get label => switch (this) {
    ClipTrimMode.start => '先頭1秒',
    ClipTrimMode.loudest => '盛り上がり1秒',
    ClipTrimMode.random => 'ランダム1秒',
  };
}
