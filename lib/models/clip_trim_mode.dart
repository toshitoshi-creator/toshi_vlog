enum ClipTrimMode {
  start,
  loudest,
  random;

  String get label => switch (this) {
    ClipTrimMode.start => '先頭',
    ClipTrimMode.loudest => '盛り上がり',
    ClipTrimMode.random => 'ランダム',
  };
}
