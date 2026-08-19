import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'highlight_reel.dart';
import 'saved_compilation.dart';

/// Owns the always-existing "currently being built" [HighlightReel]s —
/// [current] for the まとめ tab's 簡易編集 and [currentEdit] for the 編集
/// tab — plus any number of saved snapshots the user chose to keep. The
/// two tabs' "current" projects are entirely independent (clips, captions,
/// BGM, everything): [currentEdit] is seeded with a one-time clone of
/// [current] the first time it's ever loaded (so 編集 doesn't start out
/// empty), but never resynced after that. Saved snapshots are likewise
/// deep copies (see [HighlightReel.cloneInto]), so editing one afterwards
/// never affects either "current" reel or any other saved compilation.
class CompilationLibrary extends ChangeNotifier {
  final HighlightReel current = HighlightReel(id: 'current');
  final HighlightReel currentEdit = HighlightReel(id: 'current_edit');

  List<SavedCompilation> _saved = [];
  final Map<String, HighlightReel> _loadedReels = {};

  List<SavedCompilation> get saved => List.unmodifiable(_saved);

  Future<File> _indexFile() async {
    final documentsDir = await getApplicationDocumentsDirectory();
    final dir = Directory('${documentsDir.path}/compilations');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return File('${dir.path}/index.json');
  }

  Future<void> load() async {
    await current.load();

    final documentsDir = await getApplicationDocumentsDirectory();
    final editDir = Directory('${documentsDir.path}/compilations/current_edit');
    final isFirstEditLoad = !await editDir.exists();
    await currentEdit.load();
    if (isFirstEditLoad && current.segments.isNotEmpty) {
      await current.cloneInto(currentEdit);
    }

    final index = await _indexFile();
    if (await index.exists()) {
      try {
        final raw = jsonDecode(await index.readAsString()) as List<dynamic>;
        _saved = raw
            .map((e) => SavedCompilation.fromJson(e as Map<String, dynamic>))
            .toList();
      } catch (_) {
        _saved = [];
      }
    }
    notifyListeners();
  }

  Future<void> _persistIndex() async {
    final index = await _indexFile();
    await index.writeAsString(
      jsonEncode(_saved.map((c) => c.toJson()).toList()),
    );
  }

  /// Returns the [HighlightReel] for [id] (`'current'` or a saved
  /// compilation's id), loading and caching it on first access.
  Future<HighlightReel> reelFor(String id) async {
    if (id == 'current') return current;
    final cached = _loadedReels[id];
    if (cached != null) return cached;
    final reel = HighlightReel(id: id);
    await reel.load();
    _loadedReels[id] = reel;
    return reel;
  }

  /// Deep-copies [source]'s state into a brand-new saved compilation and
  /// adds it to [saved]. Returns the new entry's metadata. [source] is
  /// whichever reel the caller is actually looking at — [current],
  /// [currentEdit], or an already-saved one being viewed — not assumed.
  Future<SavedCompilation> saveAsNew(
    HighlightReel source, {
    String? title,
  }) async {
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    final reel = HighlightReel(id: id);
    await source.cloneInto(reel);
    _loadedReels[id] = reel;

    final entry = SavedCompilation(
      id: id,
      title: title?.trim().isNotEmpty == true
          ? title!.trim()
          : '保存済み動画 ${_saved.length + 1}',
      savedAt: DateTime.now(),
    );
    _saved = [..._saved, entry];
    await _persistIndex();
    notifyListeners();
    return entry;
  }

  Future<void> renameSaved(String id, String title) async {
    final trimmed = title.trim();
    if (trimmed.isEmpty) return;
    _saved = [
      for (final c in _saved)
        if (c.id == id) c.copyWith(title: trimmed) else c,
    ];
    await _persistIndex();
    notifyListeners();
  }

  Future<void> deleteSaved(String id) async {
    _saved = _saved.where((c) => c.id != id).toList();
    await _persistIndex();
    final reel = _loadedReels.remove(id) ?? HighlightReel(id: id);
    await reel.deleteStorage();
    reel.dispose();
    notifyListeners();
  }

  @override
  void dispose() {
    current.dispose();
    currentEdit.dispose();
    for (final reel in _loadedReels.values) {
      reel.dispose();
    }
    super.dispose();
  }
}
