import 'dart:async';

import 'package:youtube_player_iframe/youtube_player_iframe.dart' as yt;

import '../../session/domain/syncable_player.dart';

/// YouTube via the official IFrame player. YouTube's own controls and taps are
/// disabled, so every play/pause/seek goes through Duet and stays in sync.
class YoutubeSyncPlayer implements SyncablePlayer {
  YoutubeSyncPlayer({required this.videoId, Duration start = Duration.zero})
      : controller = yt.YoutubePlayerController.fromVideoId(
          videoId: videoId,
          autoPlay: false,
          startSeconds: start.inMilliseconds / 1000,
          params: const yt.YoutubePlayerParams(
            showControls: false,
            showFullscreenButton: false,
            strictRelatedVideos: true,
            enableCaption: true,
            playsInline: true,
            pointerEvents: yt.PointerEvents.none,
          ),
        ) {
    _position = start;
    _subs.add(controller.stream.listen((value) {
      final previous = _state;
      _state = value.playerState;
      final metaDuration = value.metaData.duration;
      if (metaDuration > Duration.zero) _duration = metaDuration;
      if (value.metaData.title.isNotEmpty) title = value.metaData.title;
      _playbackRate = value.playbackRate > 0 ? value.playbackRate : _playbackRate;
      if (previous != _state) _positionStamp = _clock.elapsedMilliseconds;
      _notify();
    }));
    _subs.add(controller.videoStateStream.listen((state) {
      _position = state.position;
      _positionStamp = _clock.elapsedMilliseconds;
      _notify();
    }));
  }

  final String videoId;
  final yt.YoutubePlayerController controller;
  String? title;

  final _changes = StreamController<void>.broadcast();
  final _subs = <StreamSubscription<dynamic>>[];
  final _clock = Stopwatch()..start();
  yt.PlayerState _state = yt.PlayerState.unknown;
  Duration _position = Duration.zero;
  int _positionStamp = 0;
  Duration? _duration;
  double _playbackRate = 1;
  bool _disposed = false;

  yt.PlayerState get playerState => _state;

  @override
  bool get isReady =>
      !_disposed &&
      (_state == yt.PlayerState.cued ||
          _state == yt.PlayerState.paused ||
          _state == yt.PlayerState.playing ||
          _state == yt.PlayerState.buffering ||
          _state == yt.PlayerState.ended);

  @override
  bool get isPlaying => _state == yt.PlayerState.playing;

  @override
  bool get isBuffering => _state == yt.PlayerState.buffering;

  @override
  bool get isCompleted => _state == yt.PlayerState.ended;

  @override
  Duration get position {
    if (_state != yt.PlayerState.playing) return _position;
    final elapsed = (_clock.elapsedMilliseconds - _positionStamp).clamp(0, 1500);
    final estimate = _position + Duration(milliseconds: (elapsed * _playbackRate).round());
    final duration = _duration;
    return duration != null && estimate > duration ? duration : estimate;
  }

  @override
  Duration? get duration => _duration;

  @override
  double get rate => _playbackRate;

  @override
  bool get supportsRateNudging => false;

  @override
  Future<void> play() => controller.playVideo();

  @override
  Future<void> pause() => controller.pauseVideo();

  @override
  Future<void> seek(Duration position) async {
    _position = position;
    _positionStamp = _clock.elapsedMilliseconds;
    await controller.seekTo(seconds: position.inMilliseconds / 1000, allowSeekAhead: true);
  }

  @override
  Future<void> setRate(double rate) async {
    _playbackRate = rate;
    await controller.setPlaybackRate(rate);
  }

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
    await controller.close();
  }
}

/// Accepts a full YouTube link (watch, youtu.be, shorts, embed, live, music) or a bare id.
String? parseYoutubeId(String input) {
  final text = input.trim();
  if (RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(text)) return text;
  final fromPackage = yt.YoutubePlayerController.convertUrlToId(text);
  if (fromPackage != null && RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(fromPackage)) return fromPackage;
  final uri = Uri.tryParse(text.contains('://') ? text : 'https://$text');
  if (uri == null) return null;
  final v = uri.queryParameters['v'];
  if (v != null && RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(v)) return v;
  final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
  if (uri.host.contains('youtu.be') && segments.isNotEmpty) return _validId(segments.first);
  for (final marker in const ['shorts', 'embed', 'live', 'v']) {
    final index = segments.indexOf(marker);
    if (index != -1 && index + 1 < segments.length) return _validId(segments[index + 1]);
  }
  return null;
}

String? _validId(String candidate) => RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(candidate) ? candidate : null;
