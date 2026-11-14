import '../../session/domain/room_state.dart';

/// A movie or song file that exists on this phone.
class LocalMedia {
  const LocalMedia({
    required this.kind,
    required this.source,
    required this.title,
    required this.sizeBytes,
    required this.fingerprint,
    this.durationMs,
    this.shareId,
    this.fileName,
  });

  /// Original file name with extension (e.g. "Movie.2024.mkv"), when known.
  final String? fileName;

  /// Set when this is the partner's temporary upload streamed from the server
  /// ([source] is then a time-limited https link, not a file on this phone).
  final String? shareId;
  bool get isStreamed => shareId != null;

  final MediaKind kind;

  /// Absolute file path or Android content:// uri.
  final String source;
  final String title;
  final int sizeBytes;
  final int? durationMs;

  /// Same file on both phones ⇒ same fingerprint (see fingerprint.dart).
  final String fingerprint;

  bool get isContentUri => source.startsWith('content://');

  LocalMedia copyWith({int? durationMs, String? title, String? source}) => LocalMedia(
        kind: kind,
        source: source ?? this.source,
        title: title ?? this.title,
        sizeBytes: sizeBytes,
        fingerprint: fingerprint,
        durationMs: durationMs ?? this.durationMs,
        shareId: shareId,
        fileName: fileName,
      );
}
