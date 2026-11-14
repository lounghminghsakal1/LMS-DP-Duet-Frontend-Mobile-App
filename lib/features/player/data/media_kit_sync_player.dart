import 'dart:async';

import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../session/domain/syncable_player.dart';

/// Local movies & songs via libmpv (media_kit): plays mkv/mp4/avi/flac/mp3/…
/// straight from a file path or Android content:// uri.
class MediaKitSyncPlayer implements SyncablePlayer {
  MediaKitSyncPlayer({required bool video})
      : player = Player(
          configuration: const PlayerConfiguration(
            title: 'Duet',
            // Larger demuxer cache helps big local files on slow SD cards.
            bufferSize: 64 * 1024 * 1024,
          ),
        ) {
    if (video) videoController = VideoController(player);
    _subs.addAll([
      player.stream.position.listen((value) {
        _position = value;
        _positionStamp = _clock.elapsedMilliseconds;
        _notify();
      }),
      player.stream.playing.listen((_) {
        _positionStamp = _clock.elapsedMilliseconds;
        _notify();
      }),
      player.stream.buffering.listen((_) => _notify()),
      player.stream.duration.listen((value) {
        if (value > Duration.zero) _duration = value;
        _notify();
      }),
      player.stream.completed.listen((_) => _notify()),
      player.stream.rate.listen((_) => _notify()),
      player.stream.error.listen((message) => lastError = message),
    ]);
  }

  final Player player;
  VideoController? videoController;
  String? lastError;

  final _changes = StreamController<void>.broadcast();
  final _subs = <StreamSubscription<dynamic>>[];
  final _clock = Stopwatch()..start();
  Duration _position = Duration.zero;
  int _positionStamp = 0;
  Duration? _duration;
  bool _ready = false;
  bool _disposed = false;

  /// Opens the file paused at [start]. Completes once the duration is known.
  Future<void> open(String source, {Duration start = Duration.zero}) async {
    await player.open(Media(source, start: start > Duration.zero ? start : null), play: false);
    if (player.state.duration <= Duration.zero) {
      await player.stream.duration
          .firstWhere((d) => d > Duration.zero)
          .timeout(const Duration(seconds: 15), onTimeout: () => Duration.zero);
    }
    _duration = player.state.duration > Duration.zero ? player.state.duration : null;
    _position = player.state.position;
    _positionStamp = _clock.elapsedMilliseconds;
    _ready = true;
    _notify();
  }

  /// Loads an external subtitle file (.srt / .ass / .vtt) on this phone only.
  Future<void> loadSubtitle(String uri, {String title = 'Subtitles'}) =>
      player.setSubtitleTrack(SubtitleTrack.uri(uri, title: title));

  Future<void> disableSubtitles() => player.setSubtitleTrack(SubtitleTrack.no());

  @override
  bool get isReady => _ready && !_disposed;

  @override
  bool get isPlaying => player.state.playing;

  @override
  bool get isBuffering => player.state.buffering;

  @override
  bool get isCompleted => player.state.completed;

  @override
  Duration get position {
    if (!player.state.playing || player.state.buffering) return _position;
    // mpv reports position in steps; extrapolate between updates for precise sync.
    final elapsed = _clock.elapsedMilliseconds - _positionStamp;
    final extra = (elapsed.clamp(0, 1000) * player.state.rate).round();
    final estimate = _position + Duration(milliseconds: extra);
    final duration = _duration;
    return duration != null && estimate > duration ? duration : estimate;
  }

  @override
  Duration? get duration => _duration;

  @override
  double get rate => player.state.rate;

  @override
  bool get supportsRateNudging => true;

  @override
  Future<void> play() => player.play();

  @override
  Future<void> pause() => player.pause();

  @override
  Future<void> seek(Duration position) async {
    _position = position;
    _positionStamp = _clock.elapsedMilliseconds;
    await player.seek(position);
  }

  @override
  Future<void> setRate(double rate) => player.setRate(rate);

  @override
  Stream<void> get changes => _changes.stream;

  void _notify() {
    if (!_disposed && !_changes.isClosed) _changes.add(null);
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    for (final sub in _subs) {
      await sub.cancel();
    }
    await _changes.close();
    await player.dispose();
  }
}
