import 'package:duet/features/session/domain/room_state.dart';
import 'package:duet/features/session/domain/sync_engine.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_player.dart';

PlaybackState state({
  required bool playing,
  required int positionMs,
  required int updatedAt,
  int seq = 1,
  double rate = 1,
}) =>
    PlaybackState(playing: playing, positionMs: positionMs, rate: rate, updatedAt: updatedAt, seq: seq);

void main() {
  // Server and phone clocks are equal here; ClockSync is tested separately.
  late int Function() now;

  void withEngine(void Function(FakeAsync async, FakePlayer player, SyncEngine engine) body) {
    fakeAsync((async) {
      final origin = DateTime(2026).millisecondsSinceEpoch;
      now = () => origin + async.elapsed.inMilliseconds;
      final player = FakePlayer(() => now());
      final engine = SyncEngine(player: player, serverNow: () => now())..start();
      body(async, player, engine);
      engine.dispose();
    });
  }

  test('paused state pauses and parks at the exact position', () {
    withEngine((async, player, engine) {
      engine.apply(state(playing: false, positionMs: 61000, updatedAt: now()));
      async.flushMicrotasks();
      expect(player.isPlaying, isFalse);
      expect(player.positionMs, 61000);
    });
  });

  test('scheduled play waits for the server tick, then starts on time', () {
    withEngine((async, player, engine) {
      engine.apply(state(playing: true, positionMs: 5000, updatedAt: now() + 900));
      async.flushMicrotasks();
      expect(player.isPlaying, isFalse, reason: 'must not start before the scheduled time');
      expect(player.positionMs, 5000);
      expect(engine.scheduledStart.value, isNotNull);

      async.elapse(const Duration(milliseconds: 899));
      expect(player.isPlaying, isFalse);
      async.elapse(const Duration(milliseconds: 2));
      expect(player.isPlaying, isTrue);
      expect(engine.scheduledStart.value, isNull);

      async.elapse(const Duration(seconds: 10));
      expect((player.positionMs - engine.expectedPositionMs()).abs(), lessThan(50));
    });
  });

  test('a late play message jumps to where the partner already is', () {
    withEngine((async, player, engine) {
      engine.apply(state(playing: true, positionMs: 10000, updatedAt: now() - 2000));
      async.flushMicrotasks();
      expect(player.isPlaying, isTrue);
      expect(player.positionMs, closeTo(12000, 20));
    });
  });

  test('large drift is corrected with a seek', () {
    withEngine((async, player, engine) {
      engine.apply(state(playing: true, positionMs: 0, updatedAt: now()));
      async.elapse(const Duration(seconds: 3));
      player.skew(2500); // e.g. the phone stalled
      async.elapse(const Duration(seconds: 2));
      expect(player.ops.where((o) => o.startsWith('seek:')), isNotEmpty);
      expect((player.positionMs - engine.expectedPositionMs()).abs(), lessThan(100));
    });
  });

  test('small drift is corrected smoothly by nudging speed, then speed returns to normal', () {
    withEngine((async, player, engine) {
      engine.apply(state(playing: true, positionMs: 0, updatedAt: now()));
      async.elapse(const Duration(seconds: 2));
      final seeksBefore = player.ops.where((o) => o.startsWith('seek:')).length;
      player.skew(400); // 400 ms ahead
      async.elapse(const Duration(seconds: 1));
      expect(player.rate, lessThan(1), reason: 'ahead → slow down a little');
      async.elapse(const Duration(seconds: 12));
      expect((player.positionMs - engine.expectedPositionMs()).abs(), lessThan(60));
      expect(player.rate, 1.0);
      expect(player.ops.where((o) => o.startsWith('seek:')).length, seeksBefore, reason: 'no audible jump');
    });
  });

  test('stale states (older seq) are ignored, equal seq is re-applied', () {
    withEngine((async, player, engine) {
      engine.apply(state(playing: false, positionMs: 1000, updatedAt: now(), seq: 5));
      async.flushMicrotasks();
      engine.apply(state(playing: false, positionMs: 9000, updatedAt: now(), seq: 4));
      async.flushMicrotasks();
      expect(player.positionMs, 1000);

      // Optimistic local seek that the server then "rejects" by re-sending seq 5.
      engine.applyLocal(state(playing: false, positionMs: 50000, updatedAt: now(), seq: 5));
      async.flushMicrotasks();
      expect(player.positionMs, 50000);
      engine.apply(state(playing: false, positionMs: 1000, updatedAt: now(), seq: 5));
      async.flushMicrotasks();
      expect(player.positionMs, 1000);
    });
  });

  test('if something pauses the player while we should be playing, it resumes in sync', () {
    withEngine((async, player, engine) {
      engine.apply(state(playing: true, positionMs: 0, updatedAt: now()));
      async.elapse(const Duration(seconds: 2));
      player.pause();
      async.elapse(const Duration(seconds: 3));
      expect(player.isPlaying, isTrue);
      expect((player.positionMs - engine.expectedPositionMs()).abs(), lessThan(100));
    });
  });

  test('two phones with different network delays end up at the same position', () {
    fakeAsync((async) {
      final origin = DateTime(2026).millisecondsSinceEpoch;
      int server() => origin + async.elapsed.inMilliseconds;
      final a = FakePlayer(server);
      final b = FakePlayer(server);
      final engineA = SyncEngine(player: a, serverNow: server)..start();
      final engineB = SyncEngine(player: b, serverNow: server)..start();

      final play = state(playing: true, positionMs: 30000, updatedAt: server() + 900);
      engineA.apply(play); // arrives instantly
      async.elapse(const Duration(milliseconds: 350));
      engineB.apply(play); // arrives 350 ms later
      async.elapse(const Duration(seconds: 5));

      expect((a.positionMs - b.positionMs).abs(), lessThan(30));
      expect(a.positionMs, closeTo(30000 + 5350 - 900, 30));
      engineA.dispose();
      engineB.dispose();
    });
  });
}
