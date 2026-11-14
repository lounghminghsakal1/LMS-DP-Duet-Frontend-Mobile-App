import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/history_entry.dart';

/// On-device history (never sent to the server). Stored as one JSON map in
/// SharedPreferences, keyed by media fingerprint / YouTube id.
class HistoryStore {
  HistoryStore(this._prefs) {
    _load();
  }

  static const _prefsKey = 'history_v1';
  static const maxEntries = 400;

  final SharedPreferences _prefs;
  final Map<String, HistoryEntry> _entries = {};

  void _load() {
    final raw = _prefs.getString(_prefsKey);
    if (raw == null) return;
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      for (final value in decoded.values) {
        final entry = HistoryEntry.fromJson(value as Map<String, dynamic>);
        _entries[entry.key] = entry;
      }
    } catch (_) {
      // Corrupt history should never crash the app.
      _entries.clear();
    }
  }

  /// Newest first.
  List<HistoryEntry> get all {
    final list = _entries.values.toList()..sort((a, b) => b.lastPlayedAt.compareTo(a.lastPlayedAt));
    return list;
  }

  HistoryEntry? get(String key) => _entries[key];

  Future<void> put(HistoryEntry entry) async {
    _entries[entry.key] = entry;
    if (_entries.length > maxEntries) {
      final oldest = all.sublist(maxEntries);
      for (final e in oldest) {
        _entries.remove(e.key);
      }
    }
    await _save();
  }

  Future<void> remove(String key) async {
    _entries.remove(key);
    await _save();
  }

  Future<void> clear() async {
    _entries.clear();
    await _prefs.remove(_prefsKey);
  }

  Future<void> _save() async {
    final map = {for (final e in _entries.values) e.key: e.toJson()};
    await _prefs.setString(_prefsKey, jsonEncode(map));
  }
}
