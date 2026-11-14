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
  });

  final MediaKind kind;

  /// Absolute file path or Android content:// uri.
  final String source;
  final String title;
  final int sizeBytes;
  final int? durationMs;

  /// Same file on both phones ⇒ same fingerprint (see fingerprint.dart).
  final String fingerprint;

  bool get isContentUri => source.startsWith('content://');

  LocalMedia copyWith({int? durationMs, String? title}) => LocalMedia(
        kind: kind,
        source: source,
        title: title ?? this.title,
        sizeBytes: sizeBytes,
        fingerprint: fingerprint,
        durationMs: durationMs ?? this.durationMs,
      );
}
