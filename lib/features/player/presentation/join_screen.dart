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
import '../../library/domain/media_match.dart';
import '../../session/data/session_client.dart';
import '../../session/domain/room_state.dart';
import '../../session/presentation/session_controller.dart';
import '../../sharing/data/share_repository.dart';
import '../../sharing/data/stream_check.dart';
import 'watch_flow.dart';

enum _Stage { searching, notFound, requested, declined, checking, corrupted }

/// Joining what the partner started: finds the same file on this phone
/// automatically, lets you pick it (and checks it's really the same media), or —
/// if you don't have it — streams the partner's copy (deleted when you're done).
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
  bool _comparing = false;
  StreamSubscription<SessionEvent>? _eventsSub;

  // Upload speed estimate for the "about 2 min left" label.
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
      _status = media.kind == MediaKind.audio ? "This song isn't on your phone." : "This video isn't on your phone.";
    });
    // The partner may already be sharing it (e.g. you came back to the session).
    _maybeOpenStream(ref.read(sessionControllerProvider));
  }

  /// "I have it": pick the file, then check size, length and (liberally) the name.
  Future<void> _pickManually() async {
    final media = _media;
    if (media == null) return;
    final size = media.sizeBytes != null && media.sizeBytes! > 1 ? ' (${formatBytes(media.sizeBytes!)})' : '';
    final hint = 'Pick “${prettyTitle(media.title)}”$size, the same file your partner has.';
    final local = await context.push<LocalMedia>('/pick/${media.kind.name}?hint=${Uri.encodeComponent(hint)}');
    if (local == null || !mounted) return;

    setState(() => _comparing = true);
    final pickedDuration = local.durationMs ?? await ref.read(mediaLibraryProvider).probeDurationMs(local.source);
    if (!mounted) return;
    setState(() => _comparing = false);
    final match = compareMedia(
      targetFingerprint: media.fingerprint,
      targetSize: media.sizeBytes,
      targetDurationMs: media.durationMs,
      targetName: media.title,
      pickedFingerprint: local.fingerprint,
      pickedSize: local.sizeBytes,
      pickedDurationMs: pickedDuration,
      pickedName: local.fileName ?? local.title,
    );
    final picked = local.copyWith(durationMs: pickedDuration);

    switch (match.level) {
      case MatchLevel.same:
        _goWatch(WatchArgs(media: media, local: picked));
      case MatchLevel.likelySame:
        _goWatch(WatchArgs(media: media, local: picked, forceMismatch: true));
      case MatchLevel.differentCopy:
        final use = await confirmDialog(
          context,
          title: 'Another copy of the same media?',
          message: '${match.reasons.join(' · ')}\n\n'
              'It looks like the same media but not the identical file, so the timing could be slightly off.',
          confirmLabel: 'Use this file',
          cancelLabel: 'Pick another',
        );
        if (!mounted) return;
        use ? _goWatch(WatchArgs(media: media, local: picked, forceMismatch: true)) : _pickManually();
      case MatchLevel.different:
        final playAnyway = await confirmDialog(
          context,
          title: 'This isn\'t the same media',
          message: '${match.reasons.join(' · ')}\n\n'
              'Your partner is playing “${prettyTitle(media.title)}”. Pick that file so you both see the same thing.',
          confirmLabel: 'Play anyway',
          cancelLabel: 'Pick another',
          destructive: true,
        );
        if (!mounted) return;
        playAnyway ? _goWatch(WatchArgs(media: media, local: picked, forceMismatch: true)) : _pickManually();
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

  /// The shared copy didn't arrive intact: drop it and ask for a fresh upload.
  Future<void> _askAgain() async {
    final shareId = ref.read(sessionControllerProvider).share?.id;
    if (shareId != null) {
      try {
        await ref.read(shareRepositoryProvider).cancel(shareId);
      } catch (_) {}
    }
    if (mounted) _requestStream();
  }

  /// Opens the stream as soon as the partner's upload is ready — after checking
  /// that what arrived really is their file.
  Future<void> _maybeOpenStream(SessionSnapshot snapshot) async {
    final media = _media;
    final share = snapshot.share;
    if (media == null || share == null || !share.isReady || _navigated) return;
    if (_stage == _Stage.searching || _stage == _Stage.checking || _stage == _Stage.corrupted) return;
    setState(() => _stage = _Stage.checking);
    try {
      final link = await ref.read(shareRepositoryProvider).streamUrl(share.id);
      final intact = await verifySharedCopy(url: link.url, fingerprint: media.fingerprint!, sizeBytes: share.sizeBytes);
      if (!mounted) return;
      if (!intact) {
        setState(() => _stage = _Stage.corrupted);
        return;
      }
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
    } catch (_) {
      if (!mounted) return;
      showToast(context, "Couldn't reach the shared copy. Check your internet.");
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
    final speed = bytes / seconds;
    final remaining = (share.sizeBytes - share.uploadedBytes) / speed;
    final left = remaining < 60 ? 'under a minute left' : 'about ${formatSpan((remaining * 1000).round())} left';
    return '${formatBytes(speed.round())}/s · $left';
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
    final firstName = partnerName.trim().split(RegExp(r'\s+')).first;
    final share = session.share;
    final uploading = share != null && !share.isReady;
    final canStream = session.sharing.enabled && media != null && media.kind != MediaKind.youtube;
    final busy = _stage == _Stage.searching || _stage == _Stage.checking || _stage == _Stage.requested || _comparing;

    return Scaffold(
      appBar: AppBar(),
      body: DuetBackground(
        child: SafeArea(
          child: media == null
              ? const Center(child: CircularProgressIndicator())
              : LayoutBuilder(
                  builder: (context, constraints) => SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minHeight: constraints.maxHeight - 32),
                      child: IntrinsicHeight(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Spacer(),
                            Text(media.kind.emoji, textAlign: TextAlign.center, style: const TextStyle(fontSize: 52)),
                            const SizedBox(height: 14),
                            Text(
                              '$partnerName wants to ${media.kind == MediaKind.audio ? 'listen to' : 'watch'}',
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: DuetColors.textMuted),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              prettyTitle(media.title),
                              textAlign: TextAlign.center,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800, height: 1.25),
                            ),
                            if ((media.sizeBytes ?? 0) > 1 || media.durationMs != null) ...[
                              const SizedBox(height: 6),
                              Text(
                                [
                                  if (media.durationMs != null) formatPosition(media.durationMs!),
                                  if ((media.sizeBytes ?? 0) > 1) formatBytes(media.sizeBytes!),
                                ].join(' · '),
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: DuetColors.textFaint),
                              ),
                            ],
                            const SizedBox(height: 28),
                            if (uploading && _stage != _Stage.searching)
                              _UploadProgress(partnerName: partnerName, share: share, eta: _eta(share))
                            else ...[
                              if (busy) ...[
                                const Center(child: CircularProgressIndicator()),
                                const SizedBox(height: 16),
                              ],
                              Text(
                                _comparing
                                    ? 'Checking it\'s the same file…'
                                    : switch (_stage) {
                                        _Stage.requested => 'Asked $firstName to share it. Waiting for them to accept…',
                                        _Stage.declined => '$firstName can\'t share it right now.',
                                        _Stage.checking => 'Checking the shared copy…',
                                        _Stage.corrupted => 'The shared copy didn\'t arrive intact. Ask $firstName to send it again.',
                                        _ => _status,
                                      },
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: _stage == _Stage.corrupted ? DuetColors.amber : DuetColors.textMuted,
                                ),
                              ),
                            ],
                            const Spacer(),
                            const SizedBox(height: 20),
                            if (_stage == _Stage.corrupted)
                              GradientButton(label: 'Ask again', icon: Icons.refresh_rounded, onPressed: _askAgain),
                            if ((_stage == _Stage.notFound || _stage == _Stage.declined) && !_comparing) ...[
                              if (canStream) ...[
                                GradientButton(
                                  label: 'Stream $firstName\'s copy',
                                  icon: Icons.cloud_download_rounded,
                                  onPressed: partner?.online == true ? _requestStream : null,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  partner?.online == true
                                      ? '$firstName uploads it for a while and it\'s deleted when you finish. '
                                          'Uses about ${(media.sizeBytes ?? 0) > 1 ? formatBytes(media.sizeBytes!) : 'the file size'} of your data.'
                                      : '$firstName needs to be online to share it.',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(color: DuetColors.textFaint, fontSize: 12.5),
                                ),
                                const SizedBox(height: 14),
                              ],
                              OutlinedButton.icon(
                                onPressed: _pickManually,
                                icon: const Icon(Icons.folder_open_rounded),
                                label: const Text('I have it, choose the file'),
                              ),
                              const SizedBox(height: 8),
                              TextButton(onPressed: _start, child: const Text('Search again')),
                            ],
                          ],
                        ),
                      ),
                    ),
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
          '$partnerName is sending it to you',
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 14),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(value: share.progress, minHeight: 8),
        ),
        const SizedBox(height: 10),
        Text(
          '${(share.progress * 100).floor()}% · ${formatBytes(share.uploadedBytes)} of ${formatBytes(share.sizeBytes)}',
          textAlign: TextAlign.center,
          style: const TextStyle(color: DuetColors.textMuted, fontSize: 13),
        ),
        if (eta != null) ...[
          const SizedBox(height: 2),
          Text(eta!, textAlign: TextAlign.center, style: const TextStyle(color: DuetColors.textFaint, fontSize: 12.5)),
        ],
        const SizedBox(height: 10),
        Text(
          'When it\'s ready it starts for both of you together.',
          textAlign: TextAlign.center,
          style: TextStyle(color: context.palette.accent, fontSize: 12.5, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}
