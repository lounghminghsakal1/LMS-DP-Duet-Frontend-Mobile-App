// End-to-end: two app clients (as two phones) talking to a REAL Duet backend.
//
//   cd ../Duet-Backend-Nodejs && npm start          (or any running server)
//   DUET_TEST_SERVER=http://127.0.0.1:4747 flutter test test/e2e_sync_test.dart
//
// Skipped when DUET_TEST_SERVER is not set.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:duet/core/config/server_config.dart';
import 'package:duet/core/theme/app_mode.dart';
import 'package:duet/features/library/domain/fingerprint.dart';
import 'package:duet/features/session/data/session_client.dart';
import 'package:duet/features/session/domain/room_state.dart';
import 'package:duet/features/session/domain/sync_engine.dart';
import 'package:duet/features/sharing/data/share_repository.dart';
import 'package:duet/features/sharing/data/share_uploader.dart';
import 'package:duet/features/sharing/data/stream_check.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_player.dart';

final String? server = Platform.environment['DUET_TEST_SERVER'];

Future<Map<String, dynamic>> api(String method, String path, {String? token, Map<String, dynamic>? body}) async {
  final client = HttpClient();
  try {
    final request = await client.openUrl(method, Uri.parse('$server/api$path'));
    request.headers.contentType = ContentType.json;
    if (token != null) request.headers.set('authorization', 'Bearer $token');
    if (body != null) request.write(jsonEncode(body));
    final response = await request.close();
    final text = await response.transform(utf8.decoder).join();
    if (response.statusCode >= 400) throw StateError('$method $path → ${response.statusCode}: $text');
    return text.isEmpty ? <String, dynamic>{} : jsonDecode(text) as Map<String, dynamic>;
  } finally {
    client.close();
  }
}

Future<void> waitFor(bool Function() condition, String what, {Duration timeout = const Duration(seconds: 8)}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) throw TimeoutException('Timed out waiting for: $what');
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

int localNow() => DateTime.now().millisecondsSinceEpoch;

/// One simulated phone: realtime client + sync engine + fake player.
class Phone {
  Phone(String token) : client = SessionClient(uri: webSocketUriFor(server!), token: token) {
    player = FakePlayer(localNow);
    engine = SyncEngine(player: player, serverNow: client.serverNow)..start();
    _sub = client.changes.listen((_) {
      final room = client.room;
      if (room?.media != null) engine.apply(room!.playback);
    });
    client.connect();
  }

  final SessionClient client;
  late final FakePlayer player;
  late final SyncEngine engine;
  late final StreamSubscription<void> _sub;

  Future<void> close() async {
    await _sub.cancel();
    await engine.dispose();
    await client.dispose();
  }
}

void main() {
  setUpAll(() => HttpOverrides.global = null);

  test(
    'two phones stay in sync through the real server',
    () async {
      final stamp = DateTime.now().microsecondsSinceEpoch;
      final a = await api('POST', '/auth/register', body: {
        'email': 'alex_$stamp@duet.test',
        'password': 'password-123',
        'displayName': 'Alex',
      });
      final b = await api('POST', '/auth/register', body: {
        'email': 'sam_$stamp@duet.test',
        'password': 'password-123',
        'displayName': 'Sam',
      });
      final tokenA = a['token'] as String;
      final tokenB = b['token'] as String;

      await api('POST', '/pair/invites', token: tokenA, body: {'email': 'sam_$stamp@duet.test'});
      final overviewB = await api('GET', '/me', token: tokenB);
      final inviteId = ((overviewB['invites'] as Map)['incoming'] as List).first['id'] as String;
      await api('POST', '/pair/invites/$inviteId/accept', token: tokenB);

      final alex = Phone(tokenA);
      var sam = Phone(tokenB);
      try {
        await waitFor(
          () => [alex, sam].every((p) => p.client.isConnected && (p.client.room?.members.every((m) => m.online) ?? false)),
          'both phones online in the room',
        );
        await alex.client.syncClock();
        await sam.client.syncClock();

        // ---- load + ready
        final fingerprint = 'ab' * 32;
        alex.client.loadMedia(
          kind: MediaKind.video,
          title: 'Our Movie',
          fingerprint: fingerprint,
          sizeBytes: 123456789,
          durationMs: 2 * 60 * 60 * 1000,
        );
        await waitFor(() => [alex, sam].every((p) => p.client.room?.media?.title == 'Our Movie'), 'media loaded on both');
        alex.client.markReady(fingerprint: fingerprint);
        sam.client.markReady(fingerprint: fingerprint);
        await waitFor(() => alex.client.room!.members.every((m) => m.ready), 'both ready');

        // ---- play: both start together
        alex.client.play(60000);
        await waitFor(() => alex.player.isPlaying && sam.player.isPlaying, 'both playing');
        await Future<void>.delayed(const Duration(milliseconds: 1500));
        final gapPlaying = (alex.player.positionMs - sam.player.positionMs).abs();
        expect(gapPlaying, lessThan(150), reason: 'positions while playing: ${alex.player.positionMs} vs ${sam.player.positionMs}');
        expect(alex.player.positionMs, greaterThan(60000));

        // ---- pause from the other phone
        sam.client.pause(sam.player.positionMs);
        await waitFor(() => !alex.player.isPlaying && !sam.player.isPlaying, 'both paused');
        await Future<void>.delayed(const Duration(milliseconds: 300));
        expect((alex.player.positionMs - sam.player.positionMs).abs(), lessThan(150));

        // ---- seek
        sam.client.seek(3600000);
        await waitFor(() => (alex.player.positionMs - 3600000).abs() < 50, 'alex followed the seek');

        // ---- chat + reaction
        final chat = alex.client.events.firstWhere((e) => e is ChatMessageReceived && e.message.body == 'this scene 😍');
        sam.client.sendChat(text: 'this scene 😍', clientId: 'c-$stamp', positionMs: 3600000);
        final message = (await chat.timeout(const Duration(seconds: 5))) as ChatMessageReceived;
        expect(message.message.mediaPositionMs, 3600000);
        expect(message.message.mediaTitle, 'Our Movie');

        final reaction = alex.client.events.firstWhere((e) => e is ReactionReceived);
        sam.client.react('❤️');
        expect(((await reaction.timeout(const Duration(seconds: 5))) as ReactionReceived).emoji, '❤️');

        // ---- partner drops → auto pause → comes back → auto resume
        alex.client.play(alex.player.positionMs);
        await waitFor(() => alex.player.isPlaying && sam.player.isPlaying, 'playing again');
        await sam.close();
        await waitFor(() => !alex.player.isPlaying, 'auto-paused after partner left', timeout: const Duration(seconds: 12));
        expect(alex.client.room!.playback.pausedReason?.reason, 'partner_left');

        sam = Phone(tokenB);
        await waitFor(() => sam.client.room?.media?.title == 'Our Movie', 'rejoined phone sees the media');
        await sam.client.syncClock();
        sam.client.markReady(fingerprint: fingerprint);
        await waitFor(() => alex.player.isPlaying && sam.player.isPlaying, 'auto-resumed for both');
        await Future<void>.delayed(const Duration(milliseconds: 1200));
        expect((alex.player.positionMs - sam.player.positionMs).abs(), lessThan(150));

        // ---- WhatsApp-style reply
        final replyArrived = alex.client.events.firstWhere(
          (e) => e is ChatMessageReceived && e.message.replyTo?.id == message.message.id,
        );
        sam.client.sendChat(text: 'same 🥹', clientId: 'reply-$stamp', replyToId: message.message.id);
        final reply = (await replyArrived.timeout(const Duration(seconds: 5))) as ChatMessageReceived;
        expect(reply.message.replyTo!.body, 'this scene 😍');

        // ---- shared theme: one phone switches it, the other follows live
        expect(sam.client.room!.mode, AppMode.general);
        await api('PUT', '/pair/mode', token: tokenA, body: {'mode': 'friends'});
        await waitFor(() => sam.client.room?.mode == AppMode.friends, 'sam got the friends theme');
        await api('PUT', '/pair/mode', token: tokenB, body: {'mode': 'love'});
        await waitFor(() => alex.client.room?.mode == AppMode.love, 'alex got the love theme');
        final me = await api('GET', '/me', token: tokenB);
        expect(me['mode'], 'love');

        // ---- partner leaves the player → "continue watching" alone
        sam.client.markUnready();
        await waitFor(() => !alex.player.isPlaying, 'paused when partner left the player');
        expect(alex.client.room!.playback.pausedReason?.reason, 'not_ready');
        alex.client.play(alex.player.positionMs, solo: true);
        await waitFor(() => alex.player.isPlaying, 'alex continues alone');

        // ---- temporary sharing: Alex has a file Sam doesn't → upload → Sam streams it
        final dir = await Directory.systemTemp.createTemp('duet_e2e');
        final file = File('${dir.path}/Our Song.mp3');
        final bytes = List<int>.generate(23 * 1024 * 1024 + 77, (i) => (i * 7 + 3) % 256);
        await file.writeAsBytes(bytes);
        final fp = await fingerprintFile(file.path);
        alex.client.loadMedia(
          kind: MediaKind.audio,
          title: 'Our Song',
          fingerprint: fp.fingerprint,
          sizeBytes: fp.sizeBytes,
          durationMs: 120000,
        );
        await waitFor(() => sam.client.room?.media?.title == 'Our Song', 'song loaded');
        alex.client.markReady(fingerprint: fp.fingerprint); // Alex has it open locally

        final asked = alex.client.events.firstWhere((e) => e is ShareRequested);
        sam.client.requestShare();
        await asked.timeout(const Duration(seconds: 5));

        final alexRepo = ShareRepository(Dio(BaseOptions(baseUrl: '$server/api', headers: {'Authorization': 'Bearer $tokenA'})));
        final created = await alexRepo.create(
          fingerprint: fp.fingerprint,
          title: 'Our Song',
          kind: 'audio',
          sizeBytes: fp.sizeBytes,
          fileName: 'Our Song.mp3',
        );
        // ~8 parts of ≥5 MiB → uploaded over several parallel connections, each with Content-MD5.
        expect(created.share.partCount, greaterThan(3));
        await waitFor(() => sam.client.room?.startTogether == true, 'sharing waits to start together');
        var lastProgress = 0;
        await ShareUploader(repository: alexRepo).upload(
          share: created.share,
          alreadyUploaded: created.uploaded,
          openStream: file.openRead,
          onProgress: (b) {
            lastProgress = b;
            alex.client.reportShareProgress(created.share.id, b);
          },
        );
        expect(lastProgress, fp.sizeBytes);
        await waitFor(() => sam.client.room?.share?.isReady == true, 'sam sees the share is ready');

        final samRepo = ShareRepository(Dio(BaseOptions(baseUrl: '$server/api', headers: {'Authorization': 'Bearer $tokenB'})));
        final link = await samRepo.streamUrl(created.share.id);
        final http = HttpClient();
        final req = await http.getUrl(Uri.parse(link.url));
        req.headers.set('Range', 'bytes=${15 * 1024 * 1024}-${15 * 1024 * 1024 + 9}');
        final res = await req.close();
        final ranged = await res.fold<List<int>>([], (all, chunk) => all..addAll(chunk));
        expect(res.statusCode, 206);
        expect(ranged, bytes.sublist(15 * 1024 * 1024, 15 * 1024 * 1024 + 10));

        // Sam's phone checks the shared copy is intact before playing it…
        expect(await verifySharedCopy(url: link.url, fingerprint: fp.fingerprint, sizeBytes: fp.sizeBytes), isTrue);
        expect(await verifySharedCopy(url: link.url, fingerprint: 'ab' * 32, sizeBytes: fp.sizeBytes), isFalse);

        // …opens it, and because both are now ready it starts for both after a countdown.
        sam.client.markReady(fingerprint: fp.fingerprint, streaming: true);
        await waitFor(() => alex.client.room?.playback.action == 'start_together', 'start together');
        expect(alex.client.room!.playback.positionMs, 0);
        await waitFor(
          () => alex.player.isPlaying && sam.player.isPlaying,
          'both playing after the countdown',
          timeout: const Duration(seconds: 8),
        );
        await Future<void>.delayed(const Duration(milliseconds: 800));
        expect((alex.player.positionMs - sam.player.positionMs).abs(), lessThan(150));

        // Ending the session deletes the upload.
        alex.client.clearMedia();
        await waitFor(() => sam.client.room?.media == null, 'session ended');
        await Future<void>.delayed(const Duration(milliseconds: 300));
        final after = await (await http.getUrl(Uri.parse(link.url))).close();
        await after.drain<void>();
        expect(after.statusCode, 404, reason: 'shared file deleted after the session');
        http.close();
        await dir.delete(recursive: true);
      } finally {
        await alex.close();
        await sam.close();
        await api('DELETE', '/pair', token: tokenA).catchError((_) => <String, dynamic>{});
      }
    },
    skip: server == null ? 'Set DUET_TEST_SERVER=http://host:port to run against a live backend' : false,
    timeout: const Timeout(Duration(seconds: 90)),
  );
}
