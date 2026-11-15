import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart' as yt;

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/format.dart';
import '../../../core/widgets/common.dart';
import '../../chat/domain/chat_message.dart';
import '../../chat/presentation/chat_controller.dart';
import '../../chat/presentation/chat_view.dart';
import '../../history/presentation/history_controller.dart';
import '../../session/data/session_client.dart';
import '../../session/domain/room_state.dart';
import '../../session/domain/sync_engine.dart';
import '../../session/domain/syncable_player.dart';
import '../../session/presentation/presence.dart';
import '../../session/presentation/session_controller.dart';
import '../../sharing/data/share_repository.dart';
import '../../sharing/presentation/share_controller.dart';
import '../data/media_kit_sync_player.dart';
import '../data/youtube_sync_player.dart';
import 'watch_flow.dart';
import 'widgets/player_controls.dart';
import 'widgets/reaction_overlay.dart';

/// The "together" screen: player + sync + chat + reactions.
class WatchScreen extends ConsumerStatefulWidget {
  const WatchScreen({super.key, required this.args});

  final WatchArgs args;

  @override
  ConsumerState<WatchScreen> createState() => _WatchScreenState();
}

class _WatchScreenState extends ConsumerState<WatchScreen> with WidgetsBindingObserver {
  late final SessionController _session;
  late final HistoryController _history;
  late final ActiveLocalMedia _activeMedia;
  late final SyncablePlayer _player;
  StreamSubscription<String>? _streamErrorSub;
  bool _refreshingStream = false;
  DateTime? _lastStreamRefresh;
  int _streamRefreshes = 0;
  MediaKitSyncPlayer? _mediaKit;
  YoutubeSyncPlayer? _youtube;
  late final SyncEngine _engine;

  final _reactions = GlobalKey<ReactionOverlayState>();
  final _historyClock = Stopwatch()..start();
  StreamSubscription<SessionEvent>? _eventsSub;
  StreamSubscription<void>? _playerSub;
  Timer? _historyTimer;
  Timer? _bufferTimer;
  Timer? _hideControlsTimer;
  Timer? _bannerTimer;

  String? _openError;
  bool _seenOurMedia = false;
  bool _bufferingReported = false;
  bool _completionReported = false;
  bool _pendingPlay = false;
  bool _controlsVisible = true;
  bool _chatOverlayOpen = false;
  bool _leaving = false;
  bool _subtitlesLoaded = false;
  bool _historyStarted = false;
  int _lastReadySentAt = 0;
  int _lastHistoryMs = 0;
  String? _banner;

  RoomMedia get _media => widget.args.media;
  bool get _isVideo => _media.kind != MediaKind.audio;
  SessionClient? get _client => _session.client;

  // ------------------------------------------------------------------ lifecycle

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _session = ref.read(sessionControllerProvider.notifier);
    _history = ref.read(historyControllerProvider.notifier);
    _activeMedia = ref.read(activeLocalMediaProvider.notifier);
    final local = widget.args.local;
    if (local != null && !local.isStreamed) {
      // Lets "share with partner" reuse this exact file without searching.
      Future.microtask(() => _activeMedia.set(local));
    }

    if (_media.kind == MediaKind.youtube) {
      _youtube = YoutubeSyncPlayer(
        videoId: _media.youtubeId!,
        start: Duration(milliseconds: _initialPosition()),
      );
      _player = _youtube!;
    } else {
      _mediaKit = MediaKitSyncPlayer(video: _media.kind == MediaKind.video);
      _player = _mediaKit!;
      if (local?.isStreamed == true) {
        _streamErrorSub = _mediaKit!.player.stream.error.listen((_) => _refreshStream());
      }
    }

    _engine = SyncEngine(
      player: _player,
      serverNow: _session.serverNow,
      config: _media.kind == MediaKind.youtube ? SyncConfig.youtube : SyncConfig.local,
    )..start();

    _playerSub = _player.changes.listen((_) => _onPlayerChanged());
    _eventsSub = ref.read(sessionEventsProvider).stream.listen(_onSessionEvent);
    ref.listenManual(sessionControllerProvider, (previous, next) => _onSession(previous, next));
    _historyTimer = Timer.periodic(const Duration(seconds: 5), (_) => _saveHistory());

    if (_isVideo) {
      WakelockPlus.enable();
      SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    }
    _open();
    _scheduleHideControls();
  }

  int _initialPosition() {
    final room = ref.read(sessionControllerProvider).room;
    if (room?.media?.key == _media.key) {
      return room!.playback.positionAt(_session.serverNow());
    }
    return widget.args.startPositionMs;
  }

  Future<void> _open() async {
    final mediaKit = _mediaKit;
    if (mediaKit != null) {
      try {
        await mediaKit.open(widget.args.local!.source, start: Duration(milliseconds: _initialPosition()));
      } catch (error) {
        if (mounted) setState(() => _openError = "Couldn't open this file on your phone ($error).");
        return;
      }
    }
    if (!mounted) return;
    setState(() {});
    _syncWithRoom(ref.read(sessionControllerProvider));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Leaving the app while watching a video pauses it for both of you.
    if (state == AppLifecycleState.paused && _isVideo && _engine.targetPlaying) {
      _pause();
    }
    if (state == AppLifecycleState.resumed) _client?.reconnectNow();
  }

  /// Streaming links expire (or the network hiccups): get a fresh link and
  /// reopen at the right moment.
  Future<void> _refreshStream() async {
    final shareId = widget.args.local?.shareId;
    final mediaKit = _mediaKit;
    if (shareId == null || mediaKit == null || _refreshingStream || _leaving) return;
    final now = DateTime.now();
    if (_lastStreamRefresh != null && now.difference(_lastStreamRefresh!) < const Duration(seconds: 20)) return;
    // Don't loop forever on a stream that's gone: say so after a few tries.
    if (_streamRefreshes >= 3) {
      if (mounted && _openError == null) {
        setState(() => _openError = 'The shared stream stopped working. Go back and ask for it again.');
      }
      return;
    }
    _streamRefreshes++;
    _refreshingStream = true;
    _lastStreamRefresh = now;
    try {
      final link = await ref.read(shareRepositoryProvider).streamUrl(shareId);
      if (!mounted) return;
      await mediaKit.open(link.url, start: Duration(milliseconds: _engine.expectedPositionMs()));
      _engine.playerReady();
    } catch (_) {
      if (mounted) setState(() => _openError = 'The shared copy is no longer available.');
    } finally {
      _refreshingStream = false;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _saveHistory();
    _streamErrorSub?.cancel();
    final activeMedia = _activeMedia;
    final mine = widget.args.local;
    Future.microtask(() => activeMedia.clearIf(mine));
    _eventsSub?.cancel();
    _playerSub?.cancel();
    _historyTimer?.cancel();
    _bufferTimer?.cancel();
    _hideControlsTimer?.cancel();
    _bannerTimer?.cancel();
    _engine.dispose();
    _player.dispose();
    if (_isVideo) {
      WakelockPlus.disable();
      SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
    super.dispose();
  }

  // ------------------------------------------------------------------ sync

  void _onSession(SessionSnapshot? previous, SessionSnapshot next) {
    if (_leaving || !mounted) return;
    final room = next.room;

    if (next.roomLoaded && room == null) {
      _exit('You are no longer paired.');
      return;
    }
    final roomMedia = room?.media;
    if (roomMedia != null && roomMedia.key == _media.key) {
      _seenOurMedia = true;
    } else if (_seenOurMedia) {
      // Our media was replaced or cleared by the partner.
      if (roomMedia == null) {
        _exit('${next.partner?.displayName ?? 'Your partner'} ended the session.');
      } else {
        _leaving = true;
        context.pushReplacement('/join');
      }
      return;
    }
    _syncWithRoom(next);
  }

  void _syncWithRoom(SessionSnapshot snapshot) {
    final room = snapshot.room;
    if (room == null || room.media?.key != _media.key) return;
    _seenOurMedia = true;
    if (room.playback.playing) _pendingPlay = false;
    _engine.apply(room.playback);
    _ensureReady(snapshot);
    if (mounted) setState(() {});
  }

  /// Tells the server this phone has the media loaded. Self-healing: whenever the
  /// server thinks we are not ready (after a reconnect or server restart) we say it again.
  void _ensureReady(SessionSnapshot snapshot) {
    if (!_player.isReady || !snapshot.isConnected) return;
    final me = snapshot.me;
    if (me == null || me.ready) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastReadySentAt < 1500) return;
    _lastReadySentAt = now;
    _client?.markReady(
      fingerprint: widget.args.local?.fingerprint,
      force: widget.args.forceMismatch,
      durationMs: _player.duration?.inMilliseconds,
      streaming: widget.args.local?.isStreamed ?? false,
    );
    _engine.playerReady();
  }

  /// The partner left the player / lost connection while we were watching:
  /// show "Leave" / "Continue watching". Derived from the room state, so it also
  /// closes by itself when they come back (the server auto-resumes).
  PausedReason? _partnerLeft(SessionSnapshot snapshot) {
    final room = snapshot.room;
    if (room == null || room.media?.key != _media.key || room.playback.playing) return null;
    final reason = room.playback.pausedReason;
    if (reason == null || reason.userId == snapshot.myUserId) return null;
    if (reason.reason != 'partner_left' && reason.reason != 'not_ready') return null;
    return reason;
  }

  void _continueAlone() {
    HapticFeedback.selectionClick();
    _play(solo: true);
  }

  void _onPlayerChanged() {
    if (!mounted) return;
    final snapshot = ref.read(sessionControllerProvider);
    _ensureReady(snapshot);

    // Report buffering that lasts a while, so the partner waits for us.
    final target = _engine.target;
    final shouldCount = target != null && target.playing && _session.serverNow() > target.updatedAt + 500;
    if (_player.isBuffering && shouldCount && !_bufferingReported) {
      _bufferTimer ??= Timer(const Duration(milliseconds: 1500), () {
        _bufferTimer = null;
        if (_player.isBuffering && _engine.targetPlaying) {
          _bufferingReported = true;
          _client?.setBuffering(true);
        }
      });
    } else if (!_player.isBuffering) {
      _bufferTimer?.cancel();
      _bufferTimer = null;
      if (_bufferingReported) {
        _bufferingReported = false;
        _client?.setBuffering(false);
      }
    }

    // Reached the end: stop for both.
    if (_player.isCompleted && _engine.targetPlaying && !_completionReported) {
      _completionReported = true;
      final end = _player.duration?.inMilliseconds ?? _player.position.inMilliseconds;
      _client?.pause(end);
      _saveHistory();
    } else if (!_player.isCompleted) {
      _completionReported = false;
    }
  }

  // ------------------------------------------------------------------ actions

  bool _requireConnection() {
    if (_client?.isConnected == true) return true;
    _showBanner('Reconnecting… controls are paused for a moment');
    return false;
  }

  void _togglePlay() {
    _scheduleHideControls();
    if (_engine.targetPlaying) {
      _pause();
    } else {
      _play();
    }
  }

  Future<void> _play({bool solo = false}) async {
    if (!_requireConnection()) return;
    final snapshot = ref.read(sessionControllerProvider);
    final share = snapshot.share;
    final partner = snapshot.partner;
    // A shared movie starts for both automatically once the partner has it open.
    if (!solo && share != null && partner != null && !partner.ready) {
      final firstName = partner.displayName.split(' ').first;
      final status = share.isReady ? 'is opening it' : 'is getting it (${(share.progress * 100).floor()}%)';
      final startAlone = await confirmDialog(
        context,
        title: 'It starts together',
        message: '$firstName $status. As soon as $firstName is ready it starts for both of you at the same moment.',
        confirmLabel: 'Start alone',
        cancelLabel: 'Wait together',
      );
      if (!startAlone || !mounted) return;
      solo = true;
    }
    final waiting = (snapshot.room?.waitingFor ?? const []).where((m) => m.userId != snapshot.myUserId).toList();
    if (waiting.isNotEmpty && !solo) {
      final names = waiting.map((m) => m.displayName).join(' & ');
      final startAnyway = await confirmDialog(
        context,
        title: '$names isn\'t ready yet',
        message: '$names is still opening it. Start without them? They\'ll jump to where you are when they\'re ready.',
        confirmLabel: 'Start without them',
        cancelLabel: 'Wait',
      );
      if (!startAnyway || !mounted) return;
      solo = true;
    }
    var position = _player.position.inMilliseconds;
    final duration = _player.duration?.inMilliseconds;
    if (duration != null && position >= duration - 1000) position = 0; // replay from the start
    setState(() => _pendingPlay = true);
    _client?.play(position, solo: solo);
    Timer(const Duration(seconds: 4), () {
      if (mounted && _pendingPlay) setState(() => _pendingPlay = false);
    });
  }

  void _pause() {
    if (!_requireConnection()) return;
    final position = _player.position.inMilliseconds;
    final target = _engine.target;
    if (target != null) {
      _engine.applyLocal(target.copyWith(playing: false, positionMs: position, updatedAt: _session.serverNow()));
    }
    _client?.pause(position);
  }

  void _seekTo(int positionMs) {
    if (!_requireConnection()) return;
    final duration = _player.duration?.inMilliseconds;
    final clamped = duration != null ? positionMs.clamp(0, duration) : positionMs.clamp(0, 1 << 31);
    final target = _engine.target;
    if (target != null) {
      _engine.applyLocal(target.copyWith(
        positionMs: clamped,
        updatedAt: _session.serverNow() + (target.playing ? 600 : 0),
      ));
    }
    _client?.seek(clamped);
    _scheduleHideControls();
  }

  void _seekBy(int deltaMs) => _seekTo(_player.position.inMilliseconds + deltaMs);

  void _setRate(double rate) {
    if (!_requireConnection()) return;
    _client?.setRate(rate);
  }

  void _react(String emoji) {
    HapticFeedback.selectionClick();
    _reactions.currentState?.add(emoji, mine: true);
    _client?.react(emoji);
  }

  void _onTimestampTap(ChatMessage message) {
    final position = message.mediaPositionMs;
    if (position == null) return;
    if (message.mediaTitle != null && message.mediaTitle != _media.title) {
      _showBanner('That moment is from “${message.mediaTitle}”');
      return;
    }
    _seekTo(position);
    _showBanner('Jumped to ${formatPosition(position)} for both of you');
  }

  Future<void> _loadSubtitles() async {
    final mediaKit = _mediaKit;
    if (mediaKit == null) return;
    if (_subtitlesLoaded) {
      await mediaKit.disableSubtitles();
      setState(() => _subtitlesLoaded = false);
      return;
    }
    final file = await FilePicker.pickFile(type: FileType.any);
    if (file == null) return;
    final ext = (file.extension ?? '').toLowerCase();
    if (!const ['srt', 'ass', 'ssa', 'vtt', 'sub'].contains(ext)) {
      _showBanner('Pick a subtitle file (.srt, .ass, .vtt)');
      return;
    }
    await mediaKit.loadSubtitle(file.path ?? file.uri.toString(), title: file.name);
    setState(() => _subtitlesLoaded = true);
    _showBanner('Subtitles on (only on your phone)');
  }

  Future<void> _toggleFullscreen() async {
    final landscape = MediaQuery.orientationOf(context) == Orientation.landscape;
    if (landscape) {
      await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      // Let the user rotate freely again afterwards.
      Future<void>.delayed(const Duration(seconds: 2), () {
        if (mounted) SystemChrome.setPreferredOrientations(DeviceOrientation.values);
      });
    } else {
      await SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }
  }

  Future<void> _onBack() async {
    final snapshot = ref.read(sessionControllerProvider);
    final partner = snapshot.partner;
    if (partner == null || !partner.online || snapshot.media?.key != _media.key) {
      _leave(endForBoth: false);
      return;
    }
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.pause_circle_rounded, color: DuetColors.amber),
                title: const Text('Leave for now'),
                subtitle: Text('Pauses for ${partner.displayName} until you come back'),
                onTap: () => Navigator.pop(context, 'leave'),
              ),
              ListTile(
                leading: const Icon(Icons.stop_circle_rounded, color: DuetColors.danger),
                title: const Text('End for both of us'),
                onTap: () => Navigator.pop(context, 'end'),
              ),
              ListTile(
                leading: const Icon(Icons.close_rounded),
                title: const Text('Keep watching'),
                onTap: () => Navigator.pop(context),
              ),
            ],
          ),
        ),
      ),
    );
    if (choice == 'leave') _leave(endForBoth: false);
    if (choice == 'end') _leave(endForBoth: true);
  }

  void _leave({required bool endForBoth}) {
    _leaving = true;
    _saveHistory();
    if (endForBoth) {
      _client?.clearMedia();
    } else if (ref.read(sessionControllerProvider).media?.key == _media.key) {
      _client?.markUnready();
    }
    if (mounted) context.pop();
  }

  void _exit(String message) {
    if (_leaving) return;
    _leaving = true;
    _saveHistory();
    showToast(context, message);
    context.pop();
  }

  // ------------------------------------------------------------------ events & history

  void _onSessionEvent(SessionEvent event) {
    if (!mounted) return;
    final snapshot = ref.read(sessionControllerProvider);
    final myId = snapshot.myUserId;
    final partnerName = snapshot.partner?.displayName ?? 'Your partner';
    switch (event) {
      case ReactionReceived(:final emoji, :final userId) when userId != myId:
        HapticFeedback.lightImpact();
        _reactions.currentState?.add(emoji);
      case ServerErrorReceived(:final message, :final requestType)
          when requestType != null && (requestType.startsWith('playback') || requestType.startsWith('media')):
        setState(() => _pendingPlay = false);
        _showBanner(message);
      case RoomEventReceived(:final event):
        final text = _describe(event, myId, partnerName);
        if (text != null) _showBanner(text);
      default:
        break;
    }
  }

  String? _describe(RoomEvent event, String? myId, String partnerName) {
    final byPartner = event.actor != null && event.actor != myId;
    switch (event.kind) {
      case 'play' when byPartner:
        return '▶  $partnerName pressed play';
      case 'pause' when byPartner:
        return '⏸  $partnerName paused at ${formatPosition(event.positionMs ?? 0)}';
      case 'seek' when byPartner:
        return '⏩  $partnerName jumped to ${formatPosition(event.positionMs ?? 0)}';
      case 'rate' when byPartner:
        return '$partnerName set the speed to ${event.rate}×';
      case 'member_ready' when byPartner:
        return event.matched == false ? '⚠  $partnerName is playing a different file' : '🎉  $partnerName is ready';
      case 'auto_pause':
        // partner_left / not_ready open the "Leave / Continue watching" popup instead.
        return event.reason == 'buffering' && byPartner ? '⏳  Waiting for $partnerName to buffer…' : null;
      case 'play_solo' when byPartner:
        return '▶  $partnerName kept watching — catching you up';
      case 'auto_resume':
        return context.copy.backTogether;
      case 'start_together':
        return '🎬  You\'re both ready, starting together';
      case 'presence' when byPartner:
        return event.online == true ? '$partnerName is back online' : '$partnerName went offline';
      default:
        return null;
    }
  }

  void _showBanner(String text) {
    _bannerTimer?.cancel();
    setState(() => _banner = text);
    _bannerTimer = Timer(const Duration(milliseconds: 2800), () {
      if (mounted) setState(() => _banner = null);
    });
  }

  void _saveHistory() {
    if (!_player.isReady) return;
    final position = _player.position.inMilliseconds;
    final elapsed = _historyClock.elapsedMilliseconds - _lastHistoryMs;
    _lastHistoryMs = _historyClock.elapsedMilliseconds;
    // No `ref` here: this also runs from dispose().
    final partner = _session.client?.partner;
    final together = _player.isPlaying && partner != null && partner.online && partner.ready;
    final local = widget.args.local;
    final firstSave = !_historyStarted;
    _historyStarted = true;
    _history.record(
          key: _media.key,
          kind: _media.kind,
          title: local?.title ?? _youtube?.title ?? _media.title,
          positionMs: position,
          durationMs: _player.duration?.inMilliseconds,
          // A streamed link expires, so it is not remembered as a source.
          source: local?.isStreamed == true ? null : local?.source,
          youtubeId: _media.youtubeId,
          sizeBytes: local?.sizeBytes,
          togetherDeltaMs: together ? elapsed.clamp(0, 15000) : 0,
          partnerName: partner?.displayName,
          newSession: firstSave,
        );
  }

  void _scheduleHideControls() {
    _hideControlsTimer?.cancel();
    if (!_controlsVisible) setState(() => _controlsVisible = true);
    _hideControlsTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && _engine.targetPlaying && _isVideo) setState(() => _controlsVisible = false);
    });
  }

  // ------------------------------------------------------------------ UI

  @override
  Widget build(BuildContext context) {
    final snapshot = ref.watch(sessionControllerProvider);
    final landscape = MediaQuery.orientationOf(context) == Orientation.landscape;
    final unread = ref.watch(chatControllerProvider.select((c) => c.unread));

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onBack();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        resizeToAvoidBottomInset: true,
        body: Stack(
          children: [
            if (landscape && _isVideo)
              _buildLandscape(snapshot, unread)
            else
              _buildPortrait(snapshot),
            Positioned.fill(child: ReactionOverlay(key: _reactions)),
            if (_partnerLeft(snapshot) case final reason?)
              Positioned.fill(
                child: _PartnerLeftModal(
                  partner: snapshot.partner,
                  reason: reason.reason,
                  onLeave: () => _leave(endForBoth: false),
                  onContinue: _continueAlone,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPortrait(SessionSnapshot snapshot) {
    return DecoratedBox(
      decoration: BoxDecoration(gradient: context.palette.backgroundGradient),
      child: SafeArea(
        child: Column(
          children: [
            if (_isVideo)
              AspectRatio(aspectRatio: 16 / 9, child: _buildVideoStage(snapshot, compact: true))
            else
              _buildAudioStage(snapshot),
            _StatusStrip(snapshot: snapshot, engine: _engine, onNudge: () => _client?.nudge('come_watch')),
            ReactionBar(onReact: _react, dense: true),
            const Divider(height: 1),
            Expanded(
              child: ChatView(
                compact: true,
                currentMediaTitle: _media.title,
                currentPositionMs: () => _player.isReady ? _player.position.inMilliseconds : null,
                onTimestampTap: _onTimestampTap,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLandscape(SessionSnapshot snapshot, int unread) {
    return Row(
      children: [
        Expanded(child: _buildVideoStage(snapshot, compact: false, unread: unread)),
        AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          width: _chatOverlayOpen ? 340 : 0,
          color: context.palette.background.withValues(alpha: 0.96),
          child: _chatOverlayOpen
              ? SafeArea(
                  left: false,
                  child: Column(
                    children: [
                      ReactionBar(onReact: _react, dense: true),
                      Expanded(
                        child: ChatView(
                          compact: true,
                          transparent: true,
                          currentMediaTitle: _media.title,
                          currentPositionMs: () => _player.isReady ? _player.position.inMilliseconds : null,
                          onTimestampTap: _onTimestampTap,
                        ),
                      ),
                    ],
                  ),
                )
              : null,
        ),
      ],
    );
  }

  /// Video (or YouTube) with the overlay controls.
  Widget _buildVideoStage(SessionSnapshot snapshot, {required bool compact, int unread = 0}) {
    final player = switch (_media.kind) {
      MediaKind.youtube => yt.YoutubePlayer(
          controller: _youtube!.controller,
          aspectRatio: 16 / 9,
          enableFullScreenOnVerticalDrag: false,
          autoFullScreen: false,
          backgroundColor: Colors.black,
        ),
      _ => Video(
          controller: _mediaKit!.videoController!,
          controls: NoVideoControls,
          wakelock: false,
          pauseUponEnteringBackgroundMode: false,
          resumeUponEnteringForegroundMode: false,
          fill: Colors.black,
        ),
    };

    return ColoredBox(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Center(child: player),
          // Catches taps so YouTube's own UI can't be used (keeps both phones in sync).
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                if (_controlsVisible && _engine.targetPlaying) {
                  setState(() => _controlsVisible = false);
                } else {
                  _scheduleHideControls();
                }
              },
              onDoubleTapDown: (details) {
                final width = context.size?.width ?? 400;
                _seekBy(details.localPosition.dx < width / 2 ? -10000 : 10000);
              },
            ),
          ),
          if (_openError != null) _ErrorPane(message: _openError!),
          if (!_player.isReady && _openError == null) const Center(child: CircularProgressIndicator()),
          _WaitingOverlay(snapshot: snapshot, engine: _engine, onNudge: () => _client?.nudge('come_watch')),
          _SharePanel(snapshot: snapshot),
          AnimatedOpacity(
            duration: const Duration(milliseconds: 200),
            opacity: _controlsVisible ? 1 : 0,
            child: IgnorePointer(
              ignoring: !_controlsVisible,
              child: DecoratedBox(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xAA000000), Color(0x22000000), Color(0x22000000), Color(0xCC000000)],
                  ),
                ),
                child: Column(
                  children: [
                    _TopBar(
                      title: _youtube?.title ?? widget.args.local?.title ?? _media.title,
                      onBack: _onBack,
                      actions: [
                        if (!compact)
                          IconButton(
                            onPressed: () => setState(() => _chatOverlayOpen = !_chatOverlayOpen),
                            icon: Badge(
                              isLabelVisible: unread > 0 && !_chatOverlayOpen,
                              label: Text('$unread'),
                              child: Icon(
                                _chatOverlayOpen ? Icons.chat_bubble_rounded : Icons.chat_bubble_outline_rounded,
                                color: Colors.white,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const Spacer(),
                    if (_player.isReady)
                      PlayerControls(
                        player: _player,
                        engine: _engine,
                        enabled: snapshot.isConnected && _openError == null,
                        pendingPlay: _pendingPlay,
                        onTogglePlay: _togglePlay,
                        onSeek: _seekTo,
                        onSeekBy: _seekBy,
                        onRate: _setRate,
                        trailing: [
                          if (_mediaKit != null)
                            IconButton(
                              tooltip: 'Subtitles (only on your phone)',
                              visualDensity: VisualDensity.compact,
                              onPressed: _loadSubtitles,
                              icon: Icon(
                                _subtitlesLoaded ? Icons.closed_caption_rounded : Icons.closed_caption_off_rounded,
                                color: _subtitlesLoaded ? context.palette.accent : Colors.white70,
                                size: 20,
                              ),
                            ),
                          IconButton(
                            tooltip: 'Fullscreen',
                            visualDensity: VisualDensity.compact,
                            onPressed: _toggleFullscreen,
                            icon: Icon(
                              compact ? Icons.fullscreen_rounded : Icons.fullscreen_exit_rounded,
                              color: Colors.white70,
                              size: 22,
                            ),
                          ),
                        ],
                      ),
                    const SizedBox(height: 4),
                  ],
                ),
              ),
            ),
          ),
          _CountdownBadge(engine: _engine, serverNow: _session.serverNow),
          _BannerView(text: _banner),
        ],
      ),
    );
  }

  Widget _buildAudioStage(SessionSnapshot snapshot) {
    final title = widget.args.local?.title ?? _media.title;
    return Stack(
      children: [
        Column(
          children: [
            _TopBar(title: 'Listening together', onBack: _onBack),
            const SizedBox(height: 8),
            PlayerTicker(
              player: _player,
              builder: (_) => SpinningDisc(spinning: _player.isPlaying, size: 170),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                title,
                maxLines: 2,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            const SizedBox(height: 8),
            if (_openError != null)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(_openError!, style: const TextStyle(color: DuetColors.danger)),
              )
            else if (_player.isReady)
              PlayerControls(
                player: _player,
                engine: _engine,
                enabled: snapshot.isConnected,
                pendingPlay: _pendingPlay,
                onTogglePlay: _togglePlay,
                onSeek: _seekTo,
                onSeekBy: _seekBy,
                onRate: _setRate,
              )
            else
              const Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()),
          ],
        ),
        _SharePanel(snapshot: snapshot),
        _CountdownBadge(engine: _engine, serverNow: _session.serverNow),
        _BannerView(text: _banner),
      ],
    );
  }
}

// ---------------------------------------------------------------------- pieces

class _TopBar extends StatelessWidget {
  const _TopBar({required this.title, required this.onBack, this.actions = const []});

  final String title;
  final VoidCallback onBack;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          onPressed: onBack,
          icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white, size: 30),
        ),
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15),
          ),
        ),
        ...actions,
        const SizedBox(width: 4),
      ],
    );
  }
}

/// Partner status + connection quality under the player.
class _StatusStrip extends StatelessWidget {
  const _StatusStrip({required this.snapshot, required this.engine, required this.onNudge});

  final SessionSnapshot snapshot;
  final SyncEngine engine;
  final VoidCallback onNudge;

  @override
  Widget build(BuildContext context) {
    final partner = snapshot.partner;
    final share = snapshot.share;
    final uploading = share != null && !share.isReady;
    final iAmUploading = uploading && share.uploaderId == snapshot.myUserId;
    final (label, color, icon) = switch (partner) {
      null => ('Not paired', DuetColors.textFaint, Icons.person_off_rounded),
      _ when !snapshot.isConnected => ('Reconnecting…', DuetColors.amber, Icons.wifi_off_rounded),
      final p when !p.online =>
        ('${p.displayName} is offline · ${presenceText(p)}', DuetColors.textFaint, Icons.cloud_off_rounded),
      final p when iAmUploading => (
          'Sharing with ${p.displayName} · ${(share.progress * 100).floor()}%',
          context.palette.accent2,
          Icons.cloud_upload_rounded,
        ),
      final p when uploading && !p.ready => (
          '${p.displayName} will stream it after the upload · ${(share.progress * 100).floor()}%',
          context.palette.accent2,
          Icons.cloud_upload_rounded,
        ),
      final p when p.buffering => ('${p.displayName} is buffering…', DuetColors.amber, Icons.hourglass_top_rounded),
      final p when !p.ready => ('${p.displayName} is getting ready…', DuetColors.amber, Icons.downloading_rounded),
      final p when p.matched == false => ('${p.displayName} has a different file', DuetColors.amber, Icons.warning_rounded),
      final p when p.streaming => ('Watching with ${p.displayName} (streaming)', DuetColors.mint, Icons.people_alt_rounded),
      final p => ('Watching with ${p.displayName}', DuetColors.mint, Icons.people_alt_rounded),
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Row(
        children: [
          if (partner != null) ...[
            EmojiAvatar(emoji: partner.avatarEmoji, size: 30, online: partner.online),
            const SizedBox(width: 8),
          ],
          Flexible(child: StatusPill(label: label, color: color, icon: icon)),
          const Spacer(),
          if (partner != null && partner.online && !partner.ready)
            TextButton(onPressed: onNudge, child: const Text('Nudge 🍿')),
        ],
      ),
    );
  }
}

/// Popup when the partner leaves mid-movie: go home, or keep watching alone.
class _PartnerLeftModal extends StatelessWidget {
  const _PartnerLeftModal({
    required this.partner,
    required this.reason,
    required this.onLeave,
    required this.onContinue,
  });

  final RoomMember? partner;

  /// partner_left (lost connection / closed the app) or not_ready (left the player).
  final String reason;
  final VoidCallback onLeave;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final name = partner?.displayName ?? 'Your partner';
    final lostConnection = reason == 'partner_left';
    return Stack(
      children: [
        const ModalBarrier(dismissible: false, color: Color(0xB3000000)),
        Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: Material(
                color: context.palette.surface,
                borderRadius: BorderRadius.circular(26),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(22, 26, 22, 18),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Stack(
                        clipBehavior: Clip.none,
                        children: [
                          EmojiAvatar(emoji: partner?.avatarEmoji ?? '💜', size: 64, online: false),
                          Positioned(
                            right: -10,
                            top: -6,
                            child: Text(lostConnection ? '📶' : '🚪', style: const TextStyle(fontSize: 22)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        lostConnection ? '$name lost connection' : '$name left the movie',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Paused for you. If $name comes back, you\'ll continue together automatically.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: DuetColors.textMuted, height: 1.4),
                      ),
                      const SizedBox(height: 22),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: onLeave,
                              icon: const Icon(Icons.home_rounded, size: 20),
                              label: const Text('Leave'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FilledButton.icon(
                              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                              onPressed: onContinue,
                              icon: const Icon(Icons.play_arrow_rounded),
                              label: const Text('Continue'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Continue keeps watching on your own',
                        style: TextStyle(color: DuetColors.textFaint, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// "Waiting for Sam…" card while the partner is still opening the file.
class _WaitingOverlay extends StatelessWidget {
  const _WaitingOverlay({required this.snapshot, required this.engine, required this.onNudge});

  final SessionSnapshot snapshot;
  final SyncEngine engine;
  final VoidCallback onNudge;

  @override
  Widget build(BuildContext context) {
    final waiting = (snapshot.room?.waitingFor ?? const []).where((m) => m.userId != snapshot.myUserId).toList();
    // While a movie is being shared, the share panel shows progress instead.
    if (waiting.isEmpty || engine.targetPlaying || snapshot.share != null) return const SizedBox.shrink();
    final name = waiting.first.displayName;
    return Align(
      alignment: Alignment.center,
      child: Container(
        margin: const EdgeInsets.all(24),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          waiting.first.buffering ? '$name is buffering…' : 'Waiting for $name to open it…',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

/// "Starting together… 3 · 2 · 1" during the scheduled-start lead time.
class _CountdownBadge extends StatefulWidget {
  const _CountdownBadge({required this.engine, required this.serverNow});

  final SyncEngine engine;
  final int Function() serverNow;

  @override
  State<_CountdownBadge> createState() => _CountdownBadgeState();
}

class _CountdownBadgeState extends State<_CountdownBadge> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (mounted && widget.engine.scheduledStart.value != null) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int?>(
      valueListenable: widget.engine.scheduledStart,
      builder: (context, startsAt, _) {
        if (startsAt == null) return const SizedBox.shrink();
        final seconds = ((startsAt - widget.serverNow()) / 1000).ceil();
        return Align(
          alignment: Alignment.center,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.8, end: 1),
            duration: const Duration(milliseconds: 300),
            builder: (context, scale, child) => Transform.scale(scale: scale, child: child),
            child: Container(
              padding: const EdgeInsets.fromLTRB(10, 8, 18, 8),
              decoration: BoxDecoration(
                gradient: context.palette.accentGradient,
                borderRadius: BorderRadius.circular(99),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (seconds >= 1)
                    Container(
                      width: 30,
                      height: 30,
                      margin: const EdgeInsets.only(right: 10),
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white),
                      child: Text(
                        '$seconds',
                        style: TextStyle(color: context.palette.accent, fontWeight: FontWeight.w900, fontSize: 16),
                      ),
                    ),
                  Text(
                    context.copy.startingTogether,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// While a movie is being shared: upload progress for both of you, and the
/// promise that it starts together once both phones are ready.
class _SharePanel extends ConsumerWidget {
  const _SharePanel({required this.snapshot});

  final SessionSnapshot snapshot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final share = snapshot.share;
    final partner = snapshot.partner;
    final room = snapshot.room;
    if (share == null || partner == null || room == null || room.playback.playing) return const SizedBox.shrink();
    if (partner.ready && (snapshot.me?.ready ?? false)) return const SizedBox.shrink();

    final firstName = partner.displayName.split(' ').first;
    final iAmUploader = share.uploaderId == snapshot.myUserId;
    final upload = ref.watch(shareControllerProvider);
    final mine = iAmUploader && upload.shareId == share.id && upload.isBusy;
    final progress = share.isReady ? 1.0 : (mine ? upload.progress : share.progress);
    final title = switch ((iAmUploader, share.isReady)) {
      (true, false) => 'Sending it to $firstName',
      (true, true) => 'Sent! Waiting for $firstName to open it…',
      (false, false) => '$firstName is sending it to you',
      (false, true) => 'Opening the shared copy…',
    };
    final details = [
      if (!share.isReady) '${(progress * 100).floor()}%',
      if (!share.isReady) '${formatBytes((share.sizeBytes * progress).round())} of ${formatBytes(share.sizeBytes)}',
      if (mine && upload.bytesPerSecond > 0) '${formatBytes(upload.bytesPerSecond.round())}/s',
      if (mine && upload.timeLeft != null)
        upload.timeLeft!.inSeconds < 60 ? 'under a minute left' : '${formatSpan(upload.timeLeft!.inMilliseconds)} left',
    ].join(' · ');

    return Align(
      alignment: Alignment.center,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 330),
        margin: const EdgeInsets.all(20),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.78),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: context.palette.outline),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(
                  share.isReady ? Icons.cloud_done_rounded : Icons.cloud_upload_rounded,
                  color: context.palette.accent,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(value: share.isReady ? null : progress, minHeight: 6),
            ),
            if (details.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(details, style: const TextStyle(color: DuetColors.textMuted, fontSize: 12)),
            ],
            const SizedBox(height: 6),
            Text(
              'Starts for both of you together when ready',
              textAlign: TextAlign.center,
              style: TextStyle(color: context.palette.accent, fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

class _BannerView extends StatelessWidget {
  const _BannerView({required this.text});

  final String? text;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 48,
      left: 16,
      right: 16,
      child: IgnorePointer(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          child: text == null
              ? const SizedBox.shrink()
              : Center(
                  key: ValueKey(text),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: context.palette.surfaceHigh.withValues(alpha: 0.95),
                      borderRadius: BorderRadius.circular(99),
                      border: Border.all(color: context.palette.outline),
                    ),
                    child: Text(text!, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                  ),
                ),
        ),
      ),
    );
  }
}

class _ErrorPane extends StatelessWidget {
  const _ErrorPane({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(message, textAlign: TextAlign.center, style: const TextStyle(color: DuetColors.danger)),
      ),
    );
  }
}
