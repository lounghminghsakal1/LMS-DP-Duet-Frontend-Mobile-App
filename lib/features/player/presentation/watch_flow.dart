import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/format.dart';
import '../../../core/widgets/common.dart';
import '../../history/domain/history_entry.dart';
import '../../history/presentation/history_controller.dart';
import '../../library/data/media_library.dart';
import '../../library/domain/local_media.dart';
import '../../session/domain/room_state.dart';
import '../../session/presentation/presence.dart';
import '../../session/presentation/session_controller.dart';

/// Everything the watch screen needs to open the media on this phone.
class WatchArgs {
  const WatchArgs({required this.media, this.local, this.startPositionMs = 0, this.forceMismatch = false});

  final RoomMedia media;

  /// The local file (null for YouTube).
  final LocalMedia? local;
  final int startPositionMs;

  /// The user chose to play a file whose fingerprint differs from the partner's.
  final bool forceMismatch;
}

/// Starting and resuming sessions from this phone.
abstract final class WatchFlow {
  /// Pick a movie/song from the device and start it for both.
  static Future<void> pickAndStart(BuildContext context, WidgetRef ref, MediaKind kind) async {
    final local = await context.push<LocalMedia>('/pick/${kind.name}');
    if (local == null || !context.mounted) return;
    await startLocal(context, ref, local);
  }

  static Future<void> startLocal(BuildContext context, WidgetRef ref, LocalMedia local) async {
    final history = ref.read(historyControllerProvider.notifier).entryFor(local.fingerprint);
    final start = await _askResume(context, history);
    if (start == null || !context.mounted) return;
    if (!await _confirmReplace(context, ref, local.title)) return;
    if (!context.mounted) return;

    final client = ref.read(sessionControllerProvider.notifier).client;
    final sent = client?.loadMedia(
          kind: local.kind,
          title: local.title,
          fingerprint: local.fingerprint,
          sizeBytes: local.sizeBytes,
          durationMs: local.durationMs ?? history?.durationMs,
          startPositionMs: start,
        ) ??
        false;
    if (!sent) {
      showToast(context, "You're offline. Reconnecting to the server…", icon: Icons.wifi_off_rounded);
      return;
    }
    final media = RoomMedia(
      kind: local.kind,
      title: local.title,
      fingerprint: local.fingerprint,
      sizeBytes: local.sizeBytes,
      durationMs: local.durationMs,
    );
    context.push('/watch', extra: WatchArgs(media: media, local: local, startPositionMs: start));
  }

  static Future<void> startYoutube(
    BuildContext context,
    WidgetRef ref, {
    required String videoId,
    required String title,
  }) async {
    final key = 'yt:$videoId';
    final history = ref.read(historyControllerProvider.notifier).entryFor(key);
    final start = await _askResume(context, history);
    if (start == null || !context.mounted) return;
    if (!await _confirmReplace(context, ref, title)) return;
    if (!context.mounted) return;

    final client = ref.read(sessionControllerProvider.notifier).client;
    final sent = client?.loadMedia(
          kind: MediaKind.youtube,
          title: title,
          youtubeId: videoId,
          durationMs: history?.durationMs,
          startPositionMs: start,
        ) ??
        false;
    if (!sent) {
      showToast(context, "You're offline. Reconnecting to the server…", icon: Icons.wifi_off_rounded);
      return;
    }
    final media = RoomMedia(kind: MediaKind.youtube, title: title, youtubeId: videoId);
    context.push('/watch', extra: WatchArgs(media: media, startPositionMs: start));
  }

  /// "Continue watching" tile: reopen the same file (or YouTube video) where we stopped.
  static Future<void> resume(BuildContext context, WidgetRef ref, HistoryEntry entry) async {
    if (entry.kind == MediaKind.youtube && entry.youtubeId != null) {
      return startYoutube(context, ref, videoId: entry.youtubeId!, title: entry.title);
    }
    final library = ref.read(mediaLibraryProvider);
    LocalMedia? local;
    if (entry.source != null) {
      local = await library.fromSource(entry.source!, entry.kind, entry.title);
    }
    if (local == null || local.fingerprint != entry.key) {
      local = await library.autoFind(
        RoomMedia(
          kind: entry.kind,
          title: entry.title,
          fingerprint: entry.key,
          sizeBytes: entry.sizeBytes,
          durationMs: entry.durationMs,
        ),
      );
    }
    if (!context.mounted) return;
    if (local == null) {
      showToast(context, "Couldn't find “${entry.title}” on this phone anymore. Pick it again.");
      return pickAndStart(context, ref, entry.kind);
    }
    return startLocal(context, ref, local.copyWith(durationMs: local.durationMs ?? entry.durationMs));
  }

  /// Returns the start position in ms, or null if the user cancelled.
  static Future<int?> _askResume(BuildContext context, HistoryEntry? entry) async {
    if (entry == null || !entry.resumable) return 0;
    final choice = await showModalBottomSheet<int>(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(entry.title, style: Theme.of(context).textTheme.titleLarge, maxLines: 2),
              const SizedBox(height: 6),
              Text(
                'You stopped at ${formatPosition(entry.positionMs)}'
                '${entry.durationMs != null ? ' of ${formatPosition(entry.durationMs!)}' : ''}'
                ' · ${formatRelative(entry.lastPlayedAt)}',
                style: const TextStyle(color: DuetColors.textMuted),
              ),
              if (entry.durationMs != null) ...[
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(value: entry.progress, minHeight: 5),
                ),
              ],
              const SizedBox(height: 20),
              GradientButton(
                label: 'Resume from ${formatPosition(entry.positionMs)}',
                icon: Icons.play_arrow_rounded,
                onPressed: () => Navigator.of(context).pop(entry.positionMs),
              ),
              const SizedBox(height: 10),
              OutlinedButton(
                onPressed: () => Navigator.of(context).pop(0),
                child: const Text('Start from the beginning'),
              ),
            ],
          ),
        ),
      ),
    );
    return choice;
  }

  /// If the partner is in the middle of something else, ask before replacing it.
  /// If they are offline, say so (they can still join later).
  static Future<bool> _confirmReplace(BuildContext context, WidgetRef ref, String newTitle) async {
    final session = ref.read(sessionControllerProvider);
    final current = session.media;
    final partner = session.partner;
    if (partner != null && !partner.online) {
      return confirmDialog(
        context,
        title: '${partner.displayName} is offline',
        message: '${partner.displayName} is ${presenceText(partner)}. Start “$newTitle” anyway? '
            'They can join from where you are as soon as they open Duet.',
        confirmLabel: 'Start anyway',
      );
    }
    if (current == null || partner == null || !partner.online || current.loadedBy == session.myUserId) {
      return true;
    }
    if (current.title == newTitle) return true;
    return confirmDialog(
      context,
      title: 'Switch for both of you?',
      message: '${partner.displayName} has “${current.title}” open. Start “$newTitle” instead?',
      confirmLabel: 'Switch',
    );
  }
}
