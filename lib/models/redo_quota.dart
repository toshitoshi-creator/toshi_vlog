import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Tracks a simple on-device "N free clip redos per day" counter, mirroring
/// [DownloadQuota]'s pattern but kept as its own file/counter since the two
/// limits are independent of each other.
///
/// Like the rest of the app's entitlement checks, there's no backend, so
/// this is trusted client-side state rather than a tamper-proof limit.
class RedoQuota extends ChangeNotifier {
  static const freeRedosPerDay = 10;

  DateTime? _countDate;
  int _count = 0;

  int get remainingFreeRedos {
    if (!_isToday(_countDate)) return freeRedosPerDay;
    return (freeRedosPerDay - _count).clamp(0, freeRedosPerDay);
  }

  bool _isToday(DateTime? date) {
    if (date == null) return false;
    final now = DateTime.now();
    return date.year == now.year &&
        date.month == now.month &&
        date.day == now.day;
  }

  Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/redo_quota.json');
  }

  Future<void> load() async {
    try {
      final file = await _file();
      if (await file.exists()) {
        final raw =
            jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        final dateStr = raw['date'] as String?;
        _countDate = dateStr != null ? DateTime.tryParse(dateStr) : null;
        _count = raw['count'] as int? ?? 0;
      }
    } catch (_) {
      _countDate = null;
      _count = 0;
    }
    notifyListeners();
  }

  Future<void> recordRedo() async {
    final now = DateTime.now();
    if (!_isToday(_countDate)) {
      _countDate = now;
      _count = 0;
    }
    _count += 1;
    notifyListeners();
    final file = await _file();
    await file.writeAsString(
      jsonEncode({'date': now.toIso8601String(), 'count': _count}),
    );
  }
}
