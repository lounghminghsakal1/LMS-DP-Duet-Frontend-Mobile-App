import 'dart:math' as math;

import '../../../core/utils/format.dart';

enum MatchLevel {
  /// Byte-identical (same fingerprint).
  same,

  /// Same size and same length — the same file for all practical purposes.
  likelySame,

  /// Same length but a different size: probably another copy/encode of the same
  /// media. Timings should line up; ask before using it.
  differentCopy,

  /// Not the media your partner is playing.
  different,
}

class MediaMatch {
  const MediaMatch(this.level, this.reasons);

  final MatchLevel level;

  /// Human-readable details ("Length 0:48 vs 3:12", …).
  final List<String> reasons;

  bool get playable => level == MatchLevel.same || level == MatchLevel.likelySame;
}

/// Compares the file someone picked with the media the partner is playing:
/// size, then duration (±2 s), then — liberally — the name.
MediaMatch compareMedia({
  required String? targetFingerprint,
  required int? targetSize,
  required int? targetDurationMs,
  required String targetName,
  required String pickedFingerprint,
  required int pickedSize,
  required int? pickedDurationMs,
  required String pickedName,
}) {
  if (targetFingerprint != null && targetFingerprint == pickedFingerprint) {
    return const MediaMatch(MatchLevel.same, []);
  }
  final sizeKnown = targetSize != null && targetSize > 1;
  final sameSize = sizeKnown && targetSize == pickedSize;
  final durationKnown = (targetDurationMs ?? 0) > 0 && (pickedDurationMs ?? 0) > 0;
  final durationDiff = durationKnown ? (targetDurationMs! - pickedDurationMs!).abs() : null;
  final sameLength = durationDiff != null && durationDiff <= 2000;
  final lengthDiffers = durationDiff != null && durationDiff > 2000;
  final similarName = namesLookAlike(targetName, pickedName);

  final reasons = <String>[
    if (durationKnown)
      sameLength
          ? 'Same length (${formatPosition(targetDurationMs!)})'
          : 'Length ${formatPosition(pickedDurationMs!)} vs ${formatPosition(targetDurationMs!)}',
    if (sizeKnown)
      sameSize ? 'Same size (${formatBytes(pickedSize)})' : 'Size ${formatBytes(pickedSize)} vs ${formatBytes(targetSize)}',
    similarName ? 'Similar name' : 'The name looks different',
  ];

  if (sameSize && !lengthDiffers) return MediaMatch(MatchLevel.likelySame, reasons);
  if (sameLength) return MediaMatch(MatchLevel.differentCopy, reasons);
  if (!durationKnown && similarName) return MediaMatch(MatchLevel.differentCopy, reasons);
  return MediaMatch(MatchLevel.different, reasons);
}

const _noise = {
  '360p', '480p', '540p', '720p', '1080p', '1440p', '2160p', '4k', '8k', 'hd', 'fhd', 'uhd', 'hq',
  'x264', 'x265', 'h264', 'h265', 'hevc', 'avc', 'aac', 'ac3', 'dts', 'mp3', 'mp4', 'mkv', 'avi', 'webm',
  'webrip', 'web', 'dl', 'webdl', 'hdrip', 'brrip', 'bdrip', 'bluray', 'dvdrip', 'hdtv', 'rip', 'proper', 'repack',
  'official', 'video', 'full', 'song', 'songs', 'lyrical', 'lyrics', 'audio', 'trailer', 'the', 'and', 'of', 'a',
};

Set<String> _tokens(String name) {
  var text = name.toLowerCase();
  text = text.replaceAll(RegExp(r'\.(mp4|m4v|mkv|avi|mov|webm|ts|3gp|mp3|m4a|flac|wav|aac|ogg|opus)$'), '');
  text = text.replaceAll(RegExp(r'[^a-z0-9\u0080-￿]+'), ' ');
  return text
      .split(' ')
      .where((w) => w.length >= 2 && !_noise.contains(w) && !RegExp(r'^\d{6,}$').hasMatch(w))
      .toSet();
}

/// Liberal name check: ignores case, separators (_ . -), quality tags (720p, x264…),
/// extensions and long timestamp numbers; at least half the words must match.
bool namesLookAlike(String a, String b) {
  final ta = _tokens(a);
  final tb = _tokens(b);
  if (ta.isEmpty || tb.isEmpty) return false;
  final common = ta.intersection(tb).length;
  return common / math.min(ta.length, tb.length) >= 0.5;
}
