class AppFont {
  const AppFont({
    required this.id,
    required this.displayName,
    required this.familyName,
  });

  final String id;
  final String displayName;

  /// Matches a `family:` entry registered in pubspec.yaml.
  final String familyName;

  static const all = <AppFont>[
    AppFont(
      id: 'sawarabi_gothic',
      displayName: 'さわらびゴシック',
      familyName: 'SawarabiGothic',
    ),
    AppFont(
      id: 'sawarabi_mincho',
      displayName: 'さわらび明朝',
      familyName: 'SawarabiMincho',
    ),
    AppFont(id: 'mplus1p', displayName: 'M PLUS 1p', familyName: 'MPLUS1p'),
    AppFont(
      id: 'mplus_rounded1c',
      displayName: 'M PLUS Rounded 1c',
      familyName: 'MPLUSRounded1c',
    ),
    AppFont(
      id: 'dot_gothic16',
      displayName: 'DotGothic16',
      familyName: 'DotGothic16',
    ),
    AppFont(
      id: 'reggae_one',
      displayName: 'Reggae One',
      familyName: 'ReggaeOne',
    ),
    AppFont(
      id: 'yusei_magic',
      displayName: 'Yusei Magic',
      familyName: 'YuseiMagic',
    ),
    AppFont(
      id: 'rampart_one',
      displayName: 'Rampart One',
      familyName: 'RampartOne',
    ),
    AppFont(id: 'yomogi', displayName: 'よもぎ', familyName: 'Yomogi'),
    AppFont(
      id: 'zen_kurenaido',
      displayName: 'Zen 紅道',
      familyName: 'ZenKurenaido',
    ),
  ];

  static AppFont byId(String id) =>
      all.firstWhere((font) => font.id == id, orElse: () => all.first);
}
