import 'dart:async';
import 'dart:math' as math;

import 'package:duet/features/session/domain/syncable_player.dart';

/// A deterministic player whose position follows a supplied clock.
class FakePlayer implements SyncablePlayer {
  FakePlayer(this.now, {this.durationMs = 2 * 60 * 60 * 1000, this.nudging = true});

  final int Function() now;
  final int durationMs;
  final bool nudging;
  final ops = <String>[];
  final _changes = StreamController<void>.broadcast();

  bool ready = true;
  bool buffering = false;
  int _basePos = 0;
  int _baseAt = 0;
  bool _playing = false;
  double _rate = 1;

  /// Simulate the device drifting by [ms].
  void skew(int ms) => _basePos += ms;

  int get positionMs => position.inMilliseconds;

  @override
  Duration get position {
    final raw = _playing ? _basePos + ((now() - _baseAt) * _rate).round() : _basePos;
    return Duration(milliseconds: math.min(math.max(raw, 0), durationMs));
  }

  @override
  Duration? get duration => Duration(milliseconds: durationMs);

  @override
  bool get isReady => ready;

  @override
  bool get isPlaying => _playing;

  @override
  bool get isBuffering => buffering;

  @override
  bool get isCompleted => positionMs >= durationMs;

  @override
  double get rate => _rate;

  @override
  bool get supportsRateNudging => nudging;

  void _rebase() {
    _basePos = positionMs;
    _baseAt = now();
  }

  @override
  Future<void> play() async {
    _rebase();
    _playing = true;
    ops.add('play');
  }

  @override
  Future<void> pause() async {
    _rebase();
    _playing = false;
    ops.add('pause');
  }

  @override
  Future<void> seek(Duration position) async {
    _basePos = position.inMilliseconds;
    _baseAt = now();
    ops.add('seek:${position.inMilliseconds}');
  }

  @override
  Future<void> setRate(double rate) async {
    _rebase();
    _rate = rate;
    ops.add('rate:$rate');
  }

  @override
  Stream<void> get changes => _changes.stream;

  @override
  Future<void> dispose() async => _changes.close();
}
