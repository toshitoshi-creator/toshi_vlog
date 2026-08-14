/// Lightweight metadata for a saved まとめ動画 snapshot. The actual video
/// data lives in the [HighlightReel] identified by [id] (see
/// [CompilationLibrary]); this only tracks what's needed to list/label it.
class SavedCompilation {
  const SavedCompilation({
    required this.id,
    required this.title,
    required this.savedAt,
  });

  final String id;
  final String title;
  final DateTime savedAt;

  SavedCompilation copyWith({String? title}) => SavedCompilation(
    id: id,
    title: title ?? this.title,
    savedAt: savedAt,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'savedAt': savedAt.toIso8601String(),
  };

  factory SavedCompilation.fromJson(Map<String, dynamic> json) =>
      SavedCompilation(
        id: json['id'] as String,
        title: json['title'] as String,
        savedAt: DateTime.parse(json['savedAt'] as String),
      );
}
