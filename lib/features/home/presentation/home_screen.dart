import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/format.dart';
import '../../../core/widgets/common.dart';
import '../../auth/presentation/server_settings_sheet.dart';
import '../../chat/presentation/chat_controller.dart';
import '../../history/domain/history_entry.dart';
import '../../history/presentation/history_controller.dart';
import '../../pairing/domain/overview.dart';
import '../../pairing/presentation/overview_controller.dart';
import '../../pairing/presentation/pairing_view.dart';
import '../../player/presentation/watch_flow.dart';
import '../../session/data/session_socket.dart';
import '../../session/domain/room_state.dart';
import '../../session/presentation/session_controller.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overview = ref.watch(overviewControllerProvider);
    final unread = ref.watch(chatControllerProvider.select((c) => c.unread));
    final paired = overview.value?.isPaired ?? false;
    final me = overview.value?.user;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 20,
        title: const Row(
          children: [
            Icon(Icons.favorite_rounded, color: DuetColors.pink, size: 22),
            SizedBox(width: 8),
            Text('Duet', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 22)),
          ],
        ),
        actions: [
          if (paired) ...[
            IconButton(
              tooltip: 'History',
              onPressed: () => context.push('/history'),
              icon: const Icon(Icons.history_rounded),
            ),
            IconButton(
              tooltip: 'Chat',
              onPressed: () => context.push('/chat'),
              icon: Badge(
                isLabelVisible: unread > 0,
                label: Text('$unread'),
                child: const Icon(Icons.chat_bubble_outline_rounded),
              ),
            ),
          ],
          Padding(
            padding: const EdgeInsets.only(right: 12, left: 4),
            child: GestureDetector(
              onTap: () => context.push('/profile'),
              child: EmojiAvatar(emoji: me?.avatarEmoji ?? '💜', size: 36),
            ),
          ),
        ],
      ),
      body: DuetBackground(
        child: overview.when(
          skipLoadingOnRefresh: true,
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => _OfflineView(
            message: error.toString(),
            onRetry: () => ref.read(overviewControllerProvider.notifier).refresh(),
          ),
          data: (data) => data.isPaired ? _PairedHome(overview: data) : PairingView(overview: data),
        ),
      ),
    );
  }
}

class _PairedHome extends ConsumerWidget {
  const _PairedHome({required this.overview});

  final Overview overview;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionControllerProvider);
    final continueWatching = ref.watch(continueWatchingProvider);
    final stats = ref.watch(togetherStatsProvider);
    final partner = overview.partner!;
    final partnerOnline = session.partner?.online ?? partner.online ?? false;
    final media = session.media;

    return RefreshIndicator(
      onRefresh: () => ref.read(overviewControllerProvider.notifier).refresh(),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
        children: [
          _CoupleHeader(
            myEmoji: overview.user.avatarEmoji,
            partnerEmoji: session.partner?.avatarEmoji ?? partner.avatarEmoji,
            partnerName: session.partner?.displayName ?? partner.displayName,
            partnerOnline: partnerOnline,
            myName: overview.user.displayName,
          ),
          if (session.connection != ConnectionStatus.connected) ...[
            const SizedBox(height: 12),
            _ConnectionBanner(connecting: session.connection == ConnectionStatus.connecting),
          ],
          if (media != null) ...[
            const SizedBox(height: 16),
            _ActiveSessionCard(
              media: media,
              startedByMe: media.loadedBy == session.myUserId,
              partnerName: session.partner?.displayName ?? partner.displayName,
              onJoin: () => context.push('/join'),
            ),
          ],
          const SizedBox(height: 24),
          const SectionTitle('What shall we do?'),
          _StartCard(
            emoji: '🎬',
            title: 'Movie night',
            subtitle: 'A movie you both have on your phones',
            gradient: DuetColors.movieGradient,
            onTap: () => WatchFlow.pickAndStart(context, ref, MediaKind.video),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _StartCard(
                  emoji: '🎵',
                  title: 'Music',
                  subtitle: 'Listen together',
                  gradient: DuetColors.musicGradient,
                  compact: true,
                  onTap: () => WatchFlow.pickAndStart(context, ref, MediaKind.audio),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StartCard(
                  emoji: '▶️',
                  title: 'YouTube',
                  subtitle: 'Paste a link',
                  gradient: DuetColors.youtubeGradient,
                  compact: true,
                  onTap: () => context.push('/youtube'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          SectionTitle('Love taps for ${partner.displayName}'),
          _LoveTaps(enabled: session.isConnected),
          if (continueWatching.isNotEmpty) ...[
            const SizedBox(height: 24),
            SectionTitle(
              'Continue watching',
              trailing: TextButton(onPressed: () => context.push('/history'), child: const Text('All')),
            ),
            SizedBox(
              height: 150,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: continueWatching.length,
                separatorBuilder: (_, _) => const SizedBox(width: 12),
                itemBuilder: (context, index) => _ContinueCard(
                  entry: continueWatching[index],
                  onTap: () => WatchFlow.resume(context, ref, continueWatching[index]),
                ),
              ),
            ),
          ],
          const SizedBox(height: 24),
          _StatsCard(stats: stats, partnerName: partner.displayName),
        ],
      ),
    );
  }
}

class _CoupleHeader extends StatelessWidget {
  const _CoupleHeader({
    required this.myEmoji,
    required this.partnerEmoji,
    required this.partnerName,
    required this.partnerOnline,
    required this.myName,
  });

  final String myEmoji;
  final String partnerEmoji;
  final String partnerName;
  final bool partnerOnline;
  final String myName;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          colors: [DuetColors.pink.withValues(alpha: 0.16), DuetColors.violet.withValues(alpha: 0.16)],
        ),
        border: Border.all(color: DuetColors.outline),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 82,
            height: 52,
            child: Stack(
              children: [
                EmojiAvatar(emoji: myEmoji, size: 52),
                Positioned(left: 30, child: EmojiAvatar(emoji: partnerEmoji, size: 52, online: partnerOnline)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$myName & $partnerName', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(
                  partnerOnline ? '$partnerName is online now 💚' : '$partnerName is offline',
                  style: TextStyle(color: partnerOnline ? DuetColors.mint : DuetColors.textMuted, fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ConnectionBanner extends StatelessWidget {
  const _ConnectionBanner({required this.connecting});

  final bool connecting;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: DuetColors.amber.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => showServerSettingsSheet(context),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              connecting
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.wifi_off_rounded, color: DuetColors.amber, size: 18),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Connecting to the Duet server… Tap to check the server address.',
                  style: TextStyle(color: DuetColors.amber, fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActiveSessionCard extends StatelessWidget {
  const _ActiveSessionCard({
    required this.media,
    required this.startedByMe,
    required this.partnerName,
    required this.onJoin,
  });

  final RoomMedia media;
  final bool startedByMe;
  final String partnerName;
  final VoidCallback onJoin;

  @override
  Widget build(BuildContext context) {
    final verb = media.kind == MediaKind.audio ? 'listening to' : 'watching';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: DuetColors.accentGradient,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [BoxShadow(color: DuetColors.pink.withValues(alpha: 0.3), blurRadius: 24, offset: const Offset(0, 10))],
      ),
      child: Row(
        children: [
          Text(media.kind.emoji, style: const TextStyle(fontSize: 34)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  startedByMe ? 'You were $verb' : '$partnerName is $verb',
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
                Text(
                  media.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 17),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: DuetColors.pink,
              minimumSize: const Size(84, 44),
            ),
            onPressed: onJoin,
            child: Text(startedByMe ? 'Open' : 'Join'),
          ),
        ],
      ),
    );
  }
}

class _StartCard extends StatelessWidget {
  const _StartCard({
    required this.emoji,
    required this.title,
    required this.subtitle,
    required this.gradient,
    required this.onTap,
    this.compact = false,
  });

  final String emoji;
  final String title;
  final String subtitle;
  final Gradient gradient;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Material(
      borderRadius: BorderRadius.circular(22),
      clipBehavior: Clip.antiAlias,
      child: Ink(
        decoration: BoxDecoration(gradient: gradient),
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.all(compact ? 16 : 20),
            child: compact
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(emoji, style: const TextStyle(fontSize: 30)),
                      const SizedBox(height: 14),
                      Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 17)),
                      Text(subtitle, style: const TextStyle(color: Colors.white70, fontSize: 12.5)),
                    ],
                  )
                : Row(
                    children: [
                      Text(emoji, style: const TextStyle(fontSize: 40)),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 20)),
                            const SizedBox(height: 2),
                            Text(subtitle, style: const TextStyle(color: Colors.white70)),
                          ],
                        ),
                      ),
                      const Icon(Icons.arrow_forward_rounded, color: Colors.white),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

class _LoveTaps extends ConsumerWidget {
  const _LoveTaps({required this.enabled});

  final bool enabled;

  static const _taps = [
    ('hug', '🤗', 'Hug'),
    ('kiss', '💋', 'Kiss'),
    ('miss_you', '🥺', 'Miss you'),
    ('come_watch', '🍿', 'Come watch'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      children: [
        for (final (kind, emoji, label) in _taps)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Material(
                color: DuetColors.surface,
                borderRadius: BorderRadius.circular(18),
                child: InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: !enabled
                      ? null
                      : () {
                          HapticFeedback.mediumImpact();
                          final sent = ref.read(sessionControllerProvider.notifier).client?.nudge(kind) ?? false;
                          showToast(context, sent ? '$emoji sent!' : "You're offline right now");
                        },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    child: Column(
                      children: [
                        Text(emoji, style: const TextStyle(fontSize: 26)),
                        const SizedBox(height: 6),
                        Text(label, style: const TextStyle(fontSize: 12, color: DuetColors.textMuted)),
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

class _ContinueCard extends StatelessWidget {
  const _ContinueCard({required this.entry, required this.onTap});

  final HistoryEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isYoutube = entry.kind == MediaKind.youtube;
    return SizedBox(
      width: 200,
      child: Material(
        color: DuetColors.surface,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 86,
                width: double.infinity,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (isYoutube && entry.youtubeId != null)
                      Image.network(
                        'https://i.ytimg.com/vi/${entry.youtubeId}/mqdefault.jpg',
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const DecoratedBox(
                          decoration: BoxDecoration(gradient: DuetColors.youtubeGradient),
                        ),
                      )
                    else
                      const DecoratedBox(
                        decoration: BoxDecoration(gradient: DuetColors.movieGradient),
                        child: Center(child: Text('🎬', style: TextStyle(fontSize: 30))),
                      ),
                    const Center(child: Icon(Icons.play_circle_fill_rounded, color: Colors.white, size: 36)),
                    Align(
                      alignment: Alignment.bottomCenter,
                      child: LinearProgressIndicator(value: entry.progress, minHeight: 3),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
                child: Text(entry.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Text(
                  'Stopped at ${formatPosition(entry.positionMs)}',
                  style: const TextStyle(color: DuetColors.textMuted, fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatsCard extends StatelessWidget {
  const _StatsCard({required this.stats, required this.partnerName});

  final TogetherStats stats;
  final String partnerName;

  @override
  Widget build(BuildContext context) {
    Widget stat(String value, String label) => Expanded(
          child: Column(
            children: [
              Text(value, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 20)),
              const SizedBox(height: 2),
              Text(label, style: const TextStyle(color: DuetColors.textMuted, fontSize: 12)),
            ],
          ),
        );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('You & $partnerName', style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(
              stats.togetherMs > 0
                  ? '${formatSpan(stats.togetherMs)} spent together on Duet 💞'
                  : 'Your time together will show up here 💞',
              style: const TextStyle(color: DuetColors.textMuted, fontSize: 13),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                stat('${stats.movies}', 'movies'),
                stat('${stats.songs}', 'songs'),
                stat('${stats.youtube}', 'videos'),
                stat('${stats.finishedMovies}', 'finished'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _OfflineView extends StatelessWidget {
  const _OfflineView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('📡', style: TextStyle(fontSize: 48)),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center, style: const TextStyle(color: DuetColors.textMuted)),
            const SizedBox(height: 20),
            FilledButton(onPressed: onRetry, child: const Text('Try again')),
            TextButton(onPressed: () => showServerSettingsSheet(context), child: const Text('Server settings')),
          ],
        ),
      ),
    );
  }
}
