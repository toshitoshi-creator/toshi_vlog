import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'highlight_reel.dart';
import 'saved_compilation.dart';

/// Owns the always-existing "currently being built" [HighlightReel]
/// (`id == 'current'`) plus any number of saved snapshots the user chose to
/// keep. Saved snapshots are deep copies (see [HighlightReel.cloneInto]),
/// so editing one afterwards never affects `current` or any other saved
/// compilation.
class CompilationLibrary extends ChangeNotifier {
  final HighlightReel current = HighlightReel(id: 'current');

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

  /// Deep-copies [current]'s state into a brand-new saved compilation and
  /// adds it to [saved]. Returns the new entry's metadata.
  Future<SavedCompilation> saveCurrentAsNew({String? title}) async {
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    final reel = HighlightReel(id: id);
    await current.cloneInto(reel);
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
    for (final reel in _loadedReels.values) {
      reel.dispose();
    }
    super.dispose();
  }
}
