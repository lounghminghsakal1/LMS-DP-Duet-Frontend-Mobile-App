import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/format.dart';
import '../../../core/widgets/common.dart';
import '../../history/presentation/history_controller.dart';
import '../../library/data/media_library.dart';
import '../../library/domain/local_media.dart';
import '../../session/data/session_client.dart';
import '../../session/domain/room_state.dart';
import '../../session/presentation/session_controller.dart';
import '../../sharing/data/share_repository.dart';
import 'watch_flow.dart';

enum _Stage { searching, notFound, requested, declined, opening }

/// Joining what the partner started: finds the same file on this phone
/// automatically, lets you pick it, or — if you don't have it — streams the
/// partner's copy while you watch (deleted when you're done).
class JoinScreen extends ConsumerStatefulWidget {
  const JoinScreen({super.key});

  @override
  ConsumerState<JoinScreen> createState() => _JoinScreenState();
}

class _JoinScreenState extends ConsumerState<JoinScreen> {
  RoomMedia? _media;
  _Stage _stage = _Stage.searching;
  String _status = 'Looking for it on your phone…';
  bool _navigated = false;
  StreamSubscription<SessionEvent>? _eventsSub;

  // Upload speed estimate for the "about 6 min left" label.
  int? _speedStartBytes;
  DateTime? _speedStartAt;

  @override
  void initState() {
    super.initState();
    _eventsSub = ref.read(sessionEventsProvider).stream.listen((event) {
      if (event is ShareDeclined && mounted && _stage == _Stage.requested) {
        setState(() => _stage = _Stage.declined);
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  @override
  void dispose() {
    _eventsSub?.cancel();
    super.dispose();
  }

  Future<void> _start() async {
    final media = ref.read(sessionControllerProvider).media;
    if (media == null) {
      if (mounted) context.pop();
      return;
    }
    setState(() {
      _media = media;
      _stage = _Stage.searching;
      _status = 'Looking for it on your phone…';
    });

    if (media.kind == MediaKind.youtube) {
      final history = ref.read(historyControllerProvider.notifier).entryFor(media.key);
      _goWatch(WatchArgs(media: media, startPositionMs: history?.positionMs ?? 0));
      return;
    }

    LocalMedia? found;
    try {
      found = await ref.read(mediaLibraryProvider).autoFind(
            media,
            onProgress: (status) {
              if (mounted) setState(() => _status = status);
            },
          );
    } catch (_) {
      found = null;
    }
    if (!mounted || _navigated) return;
    if (found != null && ref.read(sessionControllerProvider).media?.key == media.key) {
      _goWatch(WatchArgs(media: media, local: found));
      return;
    }
    setState(() {
      _stage = _Stage.notFound;
      _status = "This movie isn't on your phone.";
    });
    // The partner may already be sharing it (e.g. you came back to the session).
    _maybeOpenStream(ref.read(sessionControllerProvider));
  }

  Future<void> _pickManually() async {
    final media = _media;
    if (media == null) return;
    final size = media.sizeBytes != null ? ' (${formatBytes(media.sizeBytes!)})' : '';
    final hint = 'Pick “${media.title}”$size — the same file your partner has.';
    final local = await context.push<LocalMedia>('/pick/${media.kind.name}?hint=${Uri.encodeComponent(hint)}');
    if (local == null || !mounted) return;

    if (local.fingerprint == media.fingerprint) {
      _goWatch(WatchArgs(media: media, local: local));
      return;
    }
    final sizeNote = media.sizeBytes != null && media.sizeBytes != local.sizeBytes
        ? '\n\nYour file is ${formatBytes(local.sizeBytes)}, theirs is ${formatBytes(media.sizeBytes!)}.'
        : '';
    final playAnyway = await confirmDialog(
      context,
      title: "That's a different file",
      message: 'It does not match your partner\'s copy, so timings may not line up '
          '(e.g. a different cut or encode).$sizeNote',
      confirmLabel: 'Play anyway',
      cancelLabel: 'Pick another',
    );
    if (!mounted) return;
    if (playAnyway) {
      _goWatch(WatchArgs(media: media, local: local, forceMismatch: true));
    } else {
      _pickManually();
    }
  }

  void _requestStream() {
    final sent = ref.read(sessionControllerProvider.notifier).client?.requestShare() ?? false;
    if (!sent) {
      showToast(context, "You're offline right now.");
      return;
    }
    setState(() => _stage = _Stage.requested);
  }

  /// Opens the stream as soon as the partner's upload is ready.
  Future<void> _maybeOpenStream(SessionSnapshot snapshot) async {
    final media = _media;
    final share = snapshot.share;
    if (media == null || share == null || !share.isReady || _navigated) return;
    if (_stage == _Stage.searching || _stage == _Stage.opening) return;
    setState(() => _stage = _Stage.opening);
    try {
      final link = await ref.read(shareRepositoryProvider).streamUrl(share.id);
      if (!mounted) return;
      final history = ref.read(historyControllerProvider.notifier).entryFor(media.key);
      _goWatch(
        WatchArgs(
          media: media,
          startPositionMs: history?.positionMs ?? 0,
          local: LocalMedia(
            kind: media.kind,
            source: link.url,
            title: media.title,
            sizeBytes: share.sizeBytes,
            fingerprint: media.fingerprint!,
            durationMs: media.durationMs,
            shareId: share.id,
          ),
        ),
      );
    } on ApiException catch (error) {
      if (!mounted) return;
      showToast(context, error.message);
      setState(() => _stage = _Stage.notFound);
    }
  }

  void _goWatch(WatchArgs args) {
    if (_navigated) return;
    _navigated = true;
    context.pushReplacement('/watch', extra: args);
  }

  String? _eta(RoomShare share) {
    final now = DateTime.now();
    if (_speedStartAt == null || share.uploadedBytes < (_speedStartBytes ?? 0)) {
      _speedStartAt = now;
      _speedStartBytes = share.uploadedBytes;
      return null;
    }
    final seconds = now.difference(_speedStartAt!).inMilliseconds / 1000;
    final bytes = share.uploadedBytes - _speedStartBytes!;
    if (seconds < 3 || bytes <= 0) return null;
    final remaining = (share.sizeBytes - share.uploadedBytes) / (bytes / seconds);
    if (remaining < 60) return 'less than a minute left';
    return 'about ${formatSpan((remaining * 1000).round())} left';
  }

  @override
  Widget build(BuildContext context) {
    // Partner switched or ended while we were looking.
    ref.listen(sessionControllerProvider.select((s) => s.media?.key), (previous, next) {
      if (_navigated || _media == null) return;
      if (next == null) {
        showToast(context, 'Your partner ended the session.');
        context.pop();
      } else if (next != _media!.key) {
        _start();
      }
    });
    ref.listen(sessionControllerProvider, (_, next) => _maybeOpenStream(next));

    final session = ref.watch(sessionControllerProvider);
    final media = _media;
    final partner = session.partner;
    final partnerName = partner?.displayName ?? 'Your partner';
    final share = session.share;
    final uploading = share != null && !share.isReady;
    final canStream = session.sharing.enabled && media != null && media.kind != MediaKind.youtube;

    return Scaffold(
      appBar: AppBar(),
      body: DuetBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: media == null
                ? const Center(child: CircularProgressIndicator())
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Spacer(),
                      Text(media.kind.emoji, textAlign: TextAlign.center, style: const TextStyle(fontSize: 56)),
                      const SizedBox(height: 16),
                      Text(
                        '$partnerName wants to ${media.kind == MediaKind.audio ? 'listen to' : 'watch'}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: DuetColors.textMuted),
                      ),
                      const SizedBox(height: 6),
                      Text(media.title, textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineSmall),
                      if (media.sizeBytes != null || media.durationMs != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          [
                            if (media.durationMs != null) formatPosition(media.durationMs!),
                            if (media.sizeBytes != null) formatBytes(media.sizeBytes!),
                          ].join(' · '),
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: DuetColors.textFaint),
                        ),
                      ],
                      const SizedBox(height: 32),
                      if (uploading && _stage != _Stage.searching)
                        _UploadProgress(partnerName: partnerName, share: share, eta: _eta(share))
                      else ...[
                        if (_stage == _Stage.searching || _stage == _Stage.opening || _stage == _Stage.requested) ...[
                          const Center(child: CircularProgressIndicator()),
                          const SizedBox(height: 16),
                        ],
                        Text(
                          switch (_stage) {
                            _Stage.requested => 'Asked $partnerName to share it… waiting for them to accept',
                            _Stage.declined => '$partnerName can\'t share it right now.',
                            _Stage.opening => 'Opening the stream…',
                            _ => _status,
                          },
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: DuetColors.textMuted),
                        ),
                      ],
                      const Spacer(),
                      if (_stage == _Stage.notFound || _stage == _Stage.declined) ...[
                        if (canStream) ...[
                          GradientButton(
                            label: 'Stream from $partnerName\'s copy',
                            icon: Icons.cloud_download_rounded,
                            onPressed: partner?.online == true ? _requestStream : null,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            partner?.online == true
                                ? '$partnerName uploads it temporarily; it\'s deleted when you finish. '
                                    'Uses about ${media.sizeBytes != null ? formatBytes(media.sizeBytes!) : 'the file size'} of your data.'
                                : '$partnerName needs to be online to share it.',
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: DuetColors.textFaint, fontSize: 12.5),
                          ),
                          const SizedBox(height: 14),
                        ],
                        OutlinedButton.icon(
                          onPressed: _pickManually,
                          icon: const Icon(Icons.folder_open_rounded),
                          label: const Text('I have it — choose the file'),
                        ),
                        const SizedBox(height: 8),
                        TextButton(onPressed: _start, child: const Text('Search again')),
                      ],
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

class _UploadProgress extends StatelessWidget {
  const _UploadProgress({required this.partnerName, required this.share, this.eta});

  final String partnerName;
  final RoomShare share;
  final String? eta;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          '$partnerName is uploading it for you',
          textAlign: TextAlign.center,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 14),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(value: share.progress, minHeight: 8),
        ),
        const SizedBox(height: 10),
        Text(
          '${(share.progress * 100).floor()}% · ${formatBytes(share.uploadedBytes)} of ${formatBytes(share.sizeBytes)}'
          '${eta != null ? ' · $eta' : ''}',
          textAlign: TextAlign.center,
          style: const TextStyle(color: DuetColors.textMuted, fontSize: 13),
        ),
        const SizedBox(height: 8),
        const Text(
          'It starts automatically when the upload finishes.',
          textAlign: TextAlign.center,
          style: TextStyle(color: DuetColors.textFaint, fontSize: 12.5),
        ),
      ],
    );
  }
}
