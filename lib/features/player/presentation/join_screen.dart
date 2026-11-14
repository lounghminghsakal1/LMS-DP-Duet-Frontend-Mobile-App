import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/format.dart';
import '../../../core/widgets/common.dart';
import '../../history/presentation/history_controller.dart';
import '../../library/data/media_library.dart';
import '../../library/domain/local_media.dart';
import '../../session/domain/room_state.dart';
import '../../session/presentation/session_controller.dart';
import 'watch_flow.dart';

/// Joining what the partner started: finds the same file on this phone
/// automatically, or lets you pick it and verifies it is the same file.
class JoinScreen extends ConsumerStatefulWidget {
  const JoinScreen({super.key});

  @override
  ConsumerState<JoinScreen> createState() => _JoinScreenState();
}

class _JoinScreenState extends ConsumerState<JoinScreen> {
  RoomMedia? _media;
  String _status = 'Looking for it on your phone…';
  bool _searching = true;
  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<void> _start() async {
    final media = ref.read(sessionControllerProvider).media;
    if (media == null) {
      if (mounted) context.pop();
      return;
    }
    setState(() {
      _media = media;
      _searching = true;
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
      _searching = false;
      _status = "Couldn't find it automatically.";
    });
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

  void _goWatch(WatchArgs args) {
    if (_navigated) return;
    _navigated = true;
    context.pushReplacement('/watch', extra: args);
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

    final media = _media;
    final partner = ref.watch(sessionControllerProvider.select((s) => s.partner));

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
                        '${partner?.displayName ?? 'Your partner'} wants to ${media.kind == MediaKind.audio ? 'listen to' : 'watch'}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: DuetColors.textMuted),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        media.title,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
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
                      if (_searching) ...[
                        const Center(child: CircularProgressIndicator()),
                        const SizedBox(height: 16),
                      ],
                      Text(_status, textAlign: TextAlign.center, style: const TextStyle(color: DuetColors.textMuted)),
                      const Spacer(),
                      if (!_searching) ...[
                        const Text(
                          'Both of you need the same file on your phones. Nothing is streamed or uploaded.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: DuetColors.textFaint, fontSize: 13),
                        ),
                        const SizedBox(height: 16),
                        GradientButton(
                          label: 'Choose the file',
                          icon: Icons.folder_open_rounded,
                          onPressed: _pickManually,
                        ),
                        const SizedBox(height: 10),
                        OutlinedButton(onPressed: _start, child: const Text('Search again')),
                      ],
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
