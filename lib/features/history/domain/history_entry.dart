import '../../session/domain/room_state.dart';

/// One item of the on-device watch/listen history. Stored only on this phone.
class HistoryEntry {
  const HistoryEntry({
    required this.key,
    required this.kind,
    required this.title,
    required this.positionMs,
    required this.lastPlayedAt,
    this.durationMs,
    this.source,
    this.youtubeId,
    this.sizeBytes,
    this.togetherMs = 0,
    this.sessions = 1,
    this.partnerName,
  });

  /// File fingerprint, or `yt:{videoId}`.
  final String key;
  final MediaKind kind;
  final String title;

  /// Where we stopped last time.
  final int positionMs;
  final int? durationMs;

  /// Local file path or content:// uri, used to find the file again.
  final String? source;
  final String? youtubeId;
  final int? sizeBytes;
  final DateTime lastPlayedAt;

  /// Time spent playing while the partner was watching too.
  final int togetherMs;
  final int sessions;
  final String? partnerName;

  double get progress {
    final duration = durationMs;
    if (duration == null || duration <= 0) return 0;
    return (positionMs / duration).clamp(0, 1).toDouble();
  }

  /// Watched to the end (credits count as the end).
  bool get finished {
    final duration = durationMs;
    if (duration == null || duration <= 0) return false;
    final remaining = duration - positionMs;
    return progress >= 0.96 || remaining < (kind == MediaKind.audio ? 3000 : 45000);
  }

  /// Worth offering "Resume from …".
  bool get resumable => !finished && positionMs > 15000;

  HistoryEntry copyWith({
    String? title,
    int? positionMs,
    int? durationMs,
    String? source,
    int? sizeBytes,
    DateTime? lastPlayedAt,
    int? togetherMs,
    int? sessions,
    String? partnerName,
  }) =>
      HistoryEntry(
        key: key,
        kind: kind,
        title: title ?? this.title,
        positionMs: positionMs ?? this.positionMs,
        durationMs: durationMs ?? this.durationMs,
        source: source ?? this.source,
        youtubeId: youtubeId,
        sizeBytes: sizeBytes ?? this.sizeBytes,
        lastPlayedAt: lastPlayedAt ?? this.lastPlayedAt,
        togetherMs: togetherMs ?? this.togetherMs,
        sessions: sessions ?? this.sessions,
        partnerName: partnerName ?? this.partnerName,
      );

  Map<String, dynamic> toJson() => {
        'key': key,
        'kind': kind.name,
        'title': title,
        'positionMs': positionMs,
        'durationMs': durationMs,
        'source': source,
        'youtubeId': youtubeId,
        'sizeBytes': sizeBytes,
        'lastPlayedAt': lastPlayedAt.toIso8601String(),
        'togetherMs': togetherMs,
        'sessions': sessions,
        'partnerName': partnerName,
      };

  factory HistoryEntry.fromJson(Map<String, dynamic> json) => HistoryEntry(
        key: json['key'] as String,
        kind: MediaKind.parse(json['kind'] as String),
        title: json['title'] as String,
        positionMs: (json['positionMs'] as num?)?.toInt() ?? 0,
        durationMs: (json['durationMs'] as num?)?.toInt(),
        source: json['source'] as String?,
        youtubeId: json['youtubeId'] as String?,
        sizeBytes: (json['sizeBytes'] as num?)?.toInt(),
        lastPlayedAt: DateTime.tryParse(json['lastPlayedAt'] as String? ?? '') ?? DateTime.now(),
        togetherMs: (json['togetherMs'] as num?)?.toInt() ?? 0,
        sessions: (json['sessions'] as num?)?.toInt() ?? 1,
        partnerName: json['partnerName'] as String?,
      );
}

class TogetherStats {
  const TogetherStats({
    required this.togetherMs,
    required this.movies,
    required this.songs,
    required this.youtube,
    required this.finishedMovies,
  });

  final int togetherMs;
  final int movies;
  final int songs;
  final int youtube;
  final int finishedMovies;

  factory TogetherStats.from(Iterable<HistoryEntry> entries) {
    var together = 0, movies = 0, songs = 0, yt = 0, finished = 0;
    for (final e in entries) {
      together += e.togetherMs;
      switch (e.kind) {
        case MediaKind.video:
          movies++;
          if (e.finished) finished++;
        case MediaKind.audio:
          songs++;
        case MediaKind.youtube:
          yt++;
      }
    }
    return TogetherStats(togetherMs: together, movies: movies, songs: songs, youtube: yt, finishedMovies: finished);
  }
}
