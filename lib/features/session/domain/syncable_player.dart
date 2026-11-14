/// Anything the sync engine can drive: local video/audio (media_kit) or YouTube.
abstract class SyncablePlayer {
  /// True once the media is open and can be played / seeked.
  bool get isReady;
  bool get isPlaying;
  bool get isBuffering;
  bool get isCompleted;

  /// Best estimate of the current position (extrapolated between player updates).
  Duration get position;
  Duration? get duration;
  double get rate;

  /// Whether small speed changes can be used to catch up smoothly (no audible jump).
  bool get supportsRateNudging;

  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration position);
  Future<void> setRate(double rate);

  /// Fires whenever something the UI shows may have changed.
  Stream<void> get changes;

  Future<void> dispose();
}
