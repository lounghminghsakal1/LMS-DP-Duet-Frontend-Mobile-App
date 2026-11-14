import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'room_state.dart';
import 'syncable_player.dart';

class SyncConfig {
  const SyncConfig({
    this.hardDriftMs = 1000,
    this.softDriftMs = 140,
    this.softReleaseMs = 45,
    this.nudgeFactor = 0.05,
    this.pausedToleranceMs = 300,
    this.startToleranceMs = 400,
    this.tick = const Duration(milliseconds: 700),
  });

  /// Drift above this → jump (seek) to the right spot.
  final int hardDriftMs;

  /// Drift above this (but below hard) → play 5% faster/slower until caught up.
  final int softDriftMs;
  final int softReleaseMs;
  final double nudgeFactor;

  /// When paused, positions closer than this are considered equal.
  final int pausedToleranceMs;

  /// When (re)starting, positions closer than this skip the seek.
  final int startToleranceMs;
  final Duration tick;

  /// Local files: precise and cheap to seek.
  static const local = SyncConfig();

  /// YouTube: seeking re-buffers and speed can't be nudged, so be more tolerant.
  static const youtube = SyncConfig(
    hardDriftMs: 1600,
    pausedToleranceMs: 700,
    startToleranceMs: 900,
    tick: Duration(milliseconds: 1000),
  );
}

/// Keeps a [SyncablePlayer] in line with the server's [PlaybackState].
///
/// * paused target   → pause and park at the exact position
/// * scheduled start → park at the start position and start on the server tick
/// * playing target  → keep drift small: nudge speed for small drift, seek for big drift
class SyncEngine {
  SyncEngine({required this.player, required this.serverNow, this.config = SyncConfig.local});

  final SyncablePlayer player;
  final int Function() serverNow;
  final SyncConfig config;

  /// Server time at which a scheduled start happens (for the "starting together" countdown).
  final ValueNotifier<int?> scheduledStart = ValueNotifier<int?>(null);

  PlaybackState? _target;
  Timer? _ticker;
  Timer? _startTimer;
  Future<void> _queue = Future<void>.value();
  bool _busy = false;
  bool _nudging = false;
  bool _disposed = false;

  PlaybackState? get target => _target;
  bool get targetPlaying => _target?.playing ?? false;

  int? get _durationMs {
    final d = player.duration?.inMilliseconds;
    return d != null && d > 0 ? d : null;
  }

  /// Where the media should be right now according to the server.
  int expectedPositionMs() {
    final target = _target;
    if (target == null) return player.position.inMilliseconds;
    return target.positionAt(serverNow(), durationMs: _durationMs);
  }

  /// Current drift in ms (positive = we are ahead). Null when not comparable.
  int? get driftMs {
    final target = _target;
    if (target == null || !player.isReady) return null;
    return player.position.inMilliseconds - expectedPositionMs();
  }

  void start() {
    _ticker ??= Timer.periodic(config.tick, (_) => _tick());
  }

  /// Authoritative state from the server. Stale (older seq) states are ignored;
  /// an equal seq is re-applied, which is how a rejected optimistic action is undone.
  void apply(PlaybackState state) {
    if (_disposed) return;
    final current = _target;
    if (current != null && state.seq < current.seq) return;
    _target = state;
    _enqueue(_reconcile);
  }

  /// Optimistic change for a button pressed on this phone (pause/seek), applied
  /// before the server confirms it.
  void applyLocal(PlaybackState state) {
    if (_disposed) return;
    _target = state;
    _enqueue(_reconcile);
  }

  /// Call when the player finished opening the media.
  void playerReady() => _enqueue(_reconcile);

  Future<void> dispose() async {
    _disposed = true;
    _ticker?.cancel();
    _startTimer?.cancel();
    scheduledStart.dispose();
  }

  // ------------------------------------------------------------------ internals

  void _enqueue(Future<void> Function() op) {
    _queue = _queue.then((_) async {
      if (_disposed) return;
      _busy = true;
      try {
        await op();
      } catch (error) {
        debugPrint('SyncEngine: player operation failed: $error');
      } finally {
        _busy = false;
      }
    });
  }

  Future<void> _reconcile() async {
    final target = _target;
    if (target == null || !player.isReady) return;
    _startTimer?.cancel();
    _startTimer = null;

    if (!target.playing) {
      _setScheduledStart(null);
      if (player.isPlaying) await player.pause();
      await _resetRate(target.rate);
      final diff = (player.position.inMilliseconds - target.positionMs).abs();
      if (diff > config.pausedToleranceMs) {
        await player.seek(Duration(milliseconds: target.positionMs));
      }
      return;
    }

    await _resetRate(target.rate);
    final startsIn = target.updatedAt - serverNow();
    if (startsIn > 40) {
      // Scheduled start: wait at the start position, then both phones start on the same tick.
      if (player.isPlaying) await player.pause();
      final diff = (player.position.inMilliseconds - target.positionMs).abs();
      if (diff > 120) await player.seek(Duration(milliseconds: target.positionMs));
      _setScheduledStart(target.updatedAt);
      final remaining = math.max(0, target.updatedAt - serverNow());
      _startTimer = Timer(Duration(milliseconds: remaining), () {
        if (_disposed || !identical(_target, target)) return;
        _setScheduledStart(null);
        _enqueue(() => player.play());
      });
      return;
    }

    _setScheduledStart(null);
    final expected = target.positionAt(serverNow(), durationMs: _durationMs);
    final drift = player.position.inMilliseconds - expected;
    if (drift.abs() > config.startToleranceMs) {
      await player.seek(Duration(milliseconds: expected));
    }
    if (!player.isPlaying && !_isAtEnd(expected)) await player.play();
  }

  void _tick() {
    if (_disposed || _busy) return;
    final target = _target;
    if (target == null || !player.isReady) return;

    if (!target.playing) {
      if (player.isPlaying) _enqueue(() => player.pause());
      return;
    }

    final now = serverNow();
    if (now < target.updatedAt || player.isBuffering) return;
    final expected = target.positionAt(now, durationMs: _durationMs);

    if (!player.isPlaying) {
      if (player.isCompleted || _isAtEnd(expected)) return;
      _enqueue(() async {
        await player.seek(Duration(milliseconds: expectedPositionMs()));
        await player.play();
      });
      return;
    }

    final drift = player.position.inMilliseconds - expected;
    if (drift.abs() >= config.hardDriftMs) {
      _enqueue(() async {
        await _resetRate(target.rate);
        await player.seek(Duration(milliseconds: expectedPositionMs()));
      });
      return;
    }

    if (!player.supportsRateNudging) return;
    if (drift.abs() > config.softDriftMs) {
      final desired = target.rate * (drift > 0 ? 1 - config.nudgeFactor : 1 + config.nudgeFactor);
      if (!_nudging || (player.rate - desired).abs() > 0.001) {
        _nudging = true;
        _enqueue(() => player.setRate(desired));
      }
    } else if (_nudging && drift.abs() < config.softReleaseMs) {
      _enqueue(() => _resetRate(target.rate));
    }
  }

  Future<void> _resetRate(double rate) async {
    _nudging = false;
    if ((player.rate - rate).abs() > 0.001) await player.setRate(rate);
  }

  bool _isAtEnd(int positionMs) {
    final duration = _durationMs;
    return duration != null && positionMs >= duration - 250;
  }

  void _setScheduledStart(int? value) {
    if (!_disposed && scheduledStart.value != value) scheduledStart.value = value;
  }
}
