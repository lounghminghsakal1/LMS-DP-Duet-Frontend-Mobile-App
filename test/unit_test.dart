import 'dart:io';
import 'dart:math';

import 'package:duet/core/config/server_config.dart';
import 'package:duet/core/utils/format.dart';
import 'package:duet/features/history/data/history_store.dart';
import 'package:duet/features/history/domain/history_entry.dart';
import 'package:duet/features/library/domain/fingerprint.dart';
import 'package:duet/features/player/data/youtube_sync_player.dart';
import 'package:duet/features/session/domain/clock_sync.dart';
import 'package:duet/features/session/domain/room_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('ClockSync', () {
    test('uses the sample with the smallest round trip', () {
      var local = 1000;
      final clock = ClockSync(localNow: () => local);
      // Server is 5000 ms ahead. Slow sample (rtt 400, asymmetric) is less accurate.
      clock.addSample(t0: 1000, serverTime: 6300, t1: 1400);
      clock.addSample(t0: 2000, serverTime: 7010, t1: 2020);
      expect(clock.offsetMs, 5000);
      expect(clock.rttMs, 20);
      local = 3000;
      expect(clock.serverNow(), 8000);
    });

    test('provisional offset is replaced by real samples', () {
      final clock = ClockSync(localNow: () => 0);
      clock.setProvisional(9999);
      expect(clock.offsetMs, 9999);
      clock.addSample(t0: 0, serverTime: 100, t1: 0);
      expect(clock.offsetMs, 100);
      clock.setProvisional(5);
      expect(clock.offsetMs, 100);
    });
  });

  group('fingerprint', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('duet_fp'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('same bytes → same fingerprint from a path or a stream', () async {
      final bytes = List<int>.generate(5 * 1024 * 1024, (i) => (i * 31) % 256);
      final a = File('${dir.path}/movie.mkv')..writeAsBytesSync(bytes);
      final b = File('${dir.path}/renamed copy.mkv')..writeAsBytesSync(bytes);
      final fa = await fingerprintFile(a.path);
      final fb = await fingerprintFile(b.path);
      final fs = await fingerprintStream(b.openRead(), bytes.length);
      expect(fa.fingerprint, fb.fingerprint, reason: 'file name does not matter');
      expect(fs, fa.fingerprint);
      expect(fa.sizeBytes, bytes.length);
      expect(fa.fingerprint, matches(RegExp(r'^[a-f0-9]{64}$')));
    });

    test('different content or size → different fingerprint', () async {
      final random = Random(1);
      final bytes = List<int>.generate(1024 * 1024, (_) => random.nextInt(256));
      final a = File('${dir.path}/a.mp4')..writeAsBytesSync(bytes);
      final longer = File('${dir.path}/b.mp4')..writeAsBytesSync([...bytes, 1, 2, 3]);
      final changed = File('${dir.path}/c.mp4')..writeAsBytesSync([...bytes]..[10] = (bytes[10] + 1) % 256);
      final fa = (await fingerprintFile(a.path)).fingerprint;
      expect((await fingerprintFile(longer.path)).fingerprint, isNot(fa));
      expect((await fingerprintFile(changed.path)).fingerprint, isNot(fa));
    });
  });

  group('YouTube links', () {
    const id = 'dQw4w9WgXcQ';
    for (final link in [
      id,
      'https://www.youtube.com/watch?v=$id',
      'https://youtube.com/watch?v=$id&t=42s',
      'https://m.youtube.com/watch?feature=share&v=$id',
      'https://youtu.be/$id?si=abc123',
      'youtu.be/$id',
      'https://www.youtube.com/shorts/$id',
      'https://www.youtube.com/embed/$id',
      'https://www.youtube.com/live/$id?feature=share',
      'https://music.youtube.com/watch?v=$id&list=RD',
      '  https://youtu.be/$id  ',
    ]) {
      test('parses "$link"', () => expect(parseYoutubeId(link), id));
    }
    test('rejects garbage', () {
      expect(parseYoutubeId('hello world'), isNull);
      expect(parseYoutubeId('https://example.com/watch?v=short'), isNull);
    });
  });

  group('history', () {
    test('finished / resumable rules', () {
      HistoryEntry entry(int pos, int? dur, {MediaKind kind = MediaKind.video}) => HistoryEntry(
            key: 'k',
            kind: kind,
            title: 't',
            positionMs: pos,
            durationMs: dur,
            lastPlayedAt: DateTime(2026),
          );
      expect(entry(5000, 7200000).resumable, isFalse, reason: 'too early to bother');
      expect(entry(3600000, 7200000).resumable, isTrue);
      expect(entry(7180000, 7200000).finished, isTrue, reason: 'credits count as finished');
      expect(entry(7180000, 7200000).resumable, isFalse);
      expect(entry(100000, null).resumable, isTrue);
      expect(entry(180000, 203000, kind: MediaKind.audio).finished, isFalse);
      expect(entry(201000, 203000, kind: MediaKind.audio).finished, isTrue);
    });

    test('store persists entries across restarts, newest first', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final store = HistoryStore(prefs);
      await store.put(HistoryEntry(
        key: 'a',
        kind: MediaKind.video,
        title: 'Old movie',
        positionMs: 1000,
        lastPlayedAt: DateTime(2026, 1, 1),
      ));
      await store.put(HistoryEntry(
        key: 'yt:dQw4w9WgXcQ',
        kind: MediaKind.youtube,
        title: 'Video',
        positionMs: 42000,
        youtubeId: 'dQw4w9WgXcQ',
        lastPlayedAt: DateTime(2026, 2, 1),
        togetherMs: 60000,
      ));
      final reloaded = HistoryStore(prefs);
      expect(reloaded.all.map((e) => e.key), ['yt:dQw4w9WgXcQ', 'a']);
      expect(reloaded.get('yt:dQw4w9WgXcQ')!.positionMs, 42000);
      expect(TogetherStats.from(reloaded.all).togetherMs, 60000);
    });
  });

  group('formatting & config', () {
    test('formats positions', () {
      expect(formatPosition(0), '0:00');
      expect(formatPosition(75000), '1:15');
      expect(formatPosition(3725000), '1:02:05');
      expect(formatSpan(4500000), '1h 15m');
      expect(formatBytes(2254857830), '2.1 GB');
    });

    test('server urls', () {
      expect(normalizeServerUrl('192.168.1.26:4747/'), 'http://192.168.1.26:4747');
      expect(webSocketUriFor('http://192.168.1.26:4747').toString(), 'ws://192.168.1.26:4747/ws');
      expect(webSocketUriFor('https://duet.example.com').toString(), 'wss://duet.example.com/ws');
      expect(webSocketUriFor('https://example.com/duet').toString(), 'wss://example.com/duet/ws');
    });

    test('playback position math', () {
      const p = PlaybackState(playing: true, positionMs: 1000, rate: 1.5, updatedAt: 10000, seq: 1);
      expect(p.positionAt(9000), 1000, reason: 'before a scheduled start the position does not move');
      expect(p.positionAt(12000), 4000);
      expect(p.positionAt(12000, durationMs: 3000), 3000);
    });
  });
}
