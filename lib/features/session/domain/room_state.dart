enum MediaKind {
  video,
  audio,
  youtube;

  static MediaKind parse(String value) => MediaKind.values.firstWhere(
        (kind) => kind.name == value,
        orElse: () => MediaKind.video,
      );

  String get emoji => switch (this) {
        MediaKind.video => '🎬',
        MediaKind.audio => '🎵',
        MediaKind.youtube => '▶️',
      };

  String get label => switch (this) {
        MediaKind.video => 'Movie',
        MediaKind.audio => 'Song',
        MediaKind.youtube => 'YouTube',
      };
}

/// What is loaded in the shared room (metadata only, the file itself stays on each phone).
class RoomMedia {
  const RoomMedia({
    required this.kind,
    required this.title,
    this.fingerprint,
    this.sizeBytes,
    this.durationMs,
    this.youtubeId,
    this.loadedBy,
  });

  final MediaKind kind;
  final String title;
  final String? fingerprint;
  final int? sizeBytes;
  final int? durationMs;
  final String? youtubeId;
  final String? loadedBy;

  /// Stable identity used for history and for "is this the same media" checks.
  String get key => kind == MediaKind.youtube ? 'yt:$youtubeId' : fingerprint ?? title;

  factory RoomMedia.fromJson(Map<String, dynamic> json) => RoomMedia(
        kind: MediaKind.parse(json['kind'] as String),
        title: (json['title'] as String?) ?? 'Untitled',
        fingerprint: json['fingerprint'] as String?,
        sizeBytes: (json['sizeBytes'] as num?)?.toInt(),
        durationMs: (json['durationMs'] as num?)?.toInt(),
        youtubeId: json['youtubeId'] as String?,
        loadedBy: json['loadedBy'] as String?,
      );
}

class PausedReason {
  const PausedReason({required this.reason, required this.userId});

  /// partner_left | buffering | not_ready
  final String reason;
  final String userId;

  static PausedReason? fromJson(Object? json) {
    if (json is! Map) return null;
    return PausedReason(reason: json['reason'] as String, userId: json['userId'] as String);
  }
}

/// "At server time [updatedAt] the media was at [positionMs]; if [playing] it
/// advances at [rate]." [updatedAt] may be in the future: that is a scheduled start.
class PlaybackState {
  const PlaybackState({
    required this.playing,
    required this.positionMs,
    required this.rate,
    required this.updatedAt,
    required this.seq,
    this.by,
    this.action,
    this.pausedReason,
  });

  final bool playing;
  final int positionMs;
  final double rate;
  final int updatedAt;
  final int seq;
  final String? by;
  final String? action;
  final PausedReason? pausedReason;

  int positionAt(int serverNow, {int? durationMs}) {
    if (!playing) return positionMs;
    final elapsed = serverNow - updatedAt;
    var position = positionMs + (elapsed > 0 ? elapsed * rate : 0).round();
    if (durationMs != null && durationMs > 0 && position > durationMs) position = durationMs;
    return position;
  }

  PlaybackState copyWith({bool? playing, int? positionMs, double? rate, int? updatedAt}) => PlaybackState(
        playing: playing ?? this.playing,
        positionMs: positionMs ?? this.positionMs,
        rate: rate ?? this.rate,
        updatedAt: updatedAt ?? this.updatedAt,
        seq: seq,
        by: by,
        action: action,
        pausedReason: pausedReason,
      );

  factory PlaybackState.fromJson(Map<String, dynamic> json) => PlaybackState(
        playing: json['playing'] as bool? ?? false,
        positionMs: (json['positionMs'] as num?)?.toInt() ?? 0,
        rate: (json['rate'] as num?)?.toDouble() ?? 1,
        updatedAt: (json['updatedAt'] as num?)?.toInt() ?? 0,
        seq: (json['seq'] as num?)?.toInt() ?? 0,
        by: json['by'] as String?,
        action: json['action'] as String?,
        pausedReason: PausedReason.fromJson(json['pausedReason']),
      );
}

class RoomMember {
  const RoomMember({
    required this.userId,
    required this.displayName,
    required this.avatarEmoji,
    required this.online,
    required this.ready,
    required this.buffering,
    this.matched,
  });

  final String userId;
  final String displayName;
  final String avatarEmoji;
  final bool online;
  final bool ready;
  final bool buffering;

  /// null until they loaded the media; false when they forced a different file.
  final bool? matched;

  factory RoomMember.fromJson(Map<String, dynamic> json) => RoomMember(
        userId: json['userId'] as String,
        displayName: (json['displayName'] as String?) ?? 'Partner',
        avatarEmoji: (json['avatarEmoji'] as String?) ?? '💜',
        online: json['online'] as bool? ?? false,
        ready: json['ready'] as bool? ?? false,
        buffering: json['buffering'] as bool? ?? false,
        matched: json['matched'] as bool?,
      );
}

class RoomState {
  const RoomState({
    required this.coupleId,
    required this.media,
    required this.playback,
    required this.members,
    required this.serverTime,
  });

  final String coupleId;
  final RoomMedia? media;
  final PlaybackState playback;
  final List<RoomMember> members;
  final int serverTime;

  RoomMember? member(String? userId) {
    for (final m in members) {
      if (m.userId == userId) return m;
    }
    return null;
  }

  RoomMember? partnerOf(String? myUserId) {
    for (final m in members) {
      if (m.userId != myUserId) return m;
    }
    return null;
  }

  /// Online members that still need to load the media (or are buffering).
  List<RoomMember> get waitingFor =>
      media == null ? const [] : members.where((m) => m.online && (!m.ready || m.buffering)).toList();

  factory RoomState.fromJson(Map<String, dynamic> json) => RoomState(
        coupleId: json['coupleId'] as String,
        media: json['media'] == null ? null : RoomMedia.fromJson(json['media'] as Map<String, dynamic>),
        playback: PlaybackState.fromJson(json['playback'] as Map<String, dynamic>),
        members: [
          for (final m in (json['members'] as List? ?? const [])) RoomMember.fromJson(m as Map<String, dynamic>),
        ],
        serverTime: (json['serverTime'] as num?)?.toInt() ?? 0,
      );
}

/// Why the room changed (for toasts like "Sam paused").
class RoomEvent {
  const RoomEvent({
    required this.kind,
    this.by,
    this.userId,
    this.reason,
    this.positionMs,
    this.title,
    this.online,
    this.mediaKind,
    this.rate,
    this.buffering,
    this.matched,
  });

  final String kind;
  final String? by;
  final String? userId;
  final String? reason;
  final int? positionMs;
  final String? title;
  final bool? online;
  final String? mediaKind;
  final double? rate;
  final bool? buffering;

  /// For member_ready: false when they chose to play a different file.
  final bool? matched;

  /// Who caused the event.
  String? get actor => by ?? userId;

  factory RoomEvent.fromJson(Map<String, dynamic> json) => RoomEvent(
        kind: json['kind'] as String,
        by: json['by'] as String?,
        userId: json['userId'] as String?,
        reason: json['reason'] as String?,
        positionMs: (json['positionMs'] as num?)?.toInt(),
        title: json['title'] as String?,
        online: json['online'] as bool?,
        mediaKind: json['mediaKind'] as String?,
        rate: (json['rate'] as num?)?.toDouble(),
        buffering: json['buffering'] as bool?,
        matched: json['matched'] as bool?,
      );
}
