import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/prefs.dart';
import '../../session/domain/room_state.dart';
import '../data/history_store.dart';
import '../domain/history_entry.dart';

final historyStoreProvider = Provider<HistoryStore>((ref) => HistoryStore(ref.watch(sharedPreferencesProvider)));

class HistoryController extends Notifier<List<HistoryEntry>> {
  HistoryStore get _store => ref.read(historyStoreProvider);

  @override
  List<HistoryEntry> build() => ref.watch(historyStoreProvider).all;

  HistoryEntry? entryFor(String key) => _store.get(key);

  /// Records progress. [togetherDeltaMs] is added to the "time together" counter.
  Future<void> record({
    required String key,
    required MediaKind kind,
    required String title,
    required int positionMs,
    int? durationMs,
    String? source,
    String? youtubeId,
    int? sizeBytes,
    int togetherDeltaMs = 0,
    String? partnerName,
    bool newSession = false,
  }) async {
    final existing = _store.get(key);
    final now = DateTime.now();
    final entry = existing == null
        ? HistoryEntry(
            key: key,
            kind: kind,
            title: title,
            positionMs: positionMs,
            durationMs: durationMs,
            source: source,
            youtubeId: youtubeId,
            sizeBytes: sizeBytes,
            lastPlayedAt: now,
            togetherMs: togetherDeltaMs,
            partnerName: partnerName,
          )
        : existing.copyWith(
            title: title,
            positionMs: positionMs,
            durationMs: durationMs,
            source: source,
            sizeBytes: sizeBytes,
            lastPlayedAt: now,
            togetherMs: existing.togetherMs + togetherDeltaMs,
            sessions: existing.sessions + (newSession ? 1 : 0),
            partnerName: partnerName,
          );
    await _store.put(entry);
    state = _store.all;
  }

  Future<void> remove(String key) async {
    await _store.remove(key);
    state = _store.all;
  }

  Future<void> clear() async {
    await _store.clear();
    state = const [];
  }
}

final historyControllerProvider = NotifierProvider<HistoryController, List<HistoryEntry>>(HistoryController.new);

final togetherStatsProvider = Provider<TogetherStats>(
  (ref) => TogetherStats.from(ref.watch(historyControllerProvider)),
);

/// Unfinished movies & YouTube videos, for the "Continue watching" row.
final continueWatchingProvider = Provider<List<HistoryEntry>>((ref) {
  return ref
      .watch(historyControllerProvider)
      .where((e) => e.kind != MediaKind.audio && e.resumable)
      .take(12)
      .toList();
});
