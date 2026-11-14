import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/format.dart';
import '../../../core/widgets/common.dart';
import '../../player/presentation/watch_flow.dart';
import '../../session/domain/room_state.dart';
import '../domain/history_entry.dart';
import 'history_controller.dart';

/// Everything you played, with where you stopped. Stored only on this phone.
class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  MediaKind? _filter;

  @override
  Widget build(BuildContext context) {
    final all = ref.watch(historyControllerProvider);
    final entries = _filter == null ? all : all.where((e) => e.kind == _filter).toList();
    final stats = ref.watch(togetherStatsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('History'),
        actions: [
          if (all.isNotEmpty)
            IconButton(
              tooltip: 'Clear history',
              icon: const Icon(Icons.delete_sweep_rounded),
              onPressed: () async {
                final ok = await confirmDialog(
                  context,
                  title: 'Clear history?',
                  message: 'Resume points and stats on this phone will be removed. Your partner keeps theirs.',
                  confirmLabel: 'Clear',
                  destructive: true,
                );
                if (ok) ref.read(historyControllerProvider.notifier).clear();
              },
            ),
        ],
      ),
      body: DuetBackground(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                stats.togetherMs > 0 ? '${formatSpan(stats.togetherMs)} together so far 💞' : 'Saved on this phone only',
                style: const TextStyle(color: DuetColors.textMuted),
              ),
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  _chip(null, 'All'),
                  _chip(MediaKind.video, '🎬 Movies'),
                  _chip(MediaKind.audio, '🎵 Songs'),
                  _chip(MediaKind.youtube, '▶️ YouTube'),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: entries.isEmpty
                  ? const Center(
                      child: Text('Nothing here yet', style: TextStyle(color: DuetColors.textMuted)),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                      itemCount: entries.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final entry = entries[index];
                        return Dismissible(
                          key: ValueKey(entry.key),
                          direction: DismissDirection.endToStart,
                          background: Container(
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.only(right: 20),
                            decoration: BoxDecoration(
                              color: DuetColors.danger.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: const Icon(Icons.delete_rounded, color: DuetColors.danger),
                          ),
                          onDismissed: (_) => ref.read(historyControllerProvider.notifier).remove(entry.key),
                          child: _HistoryTile(entry: entry, onTap: () => WatchFlow.resume(context, ref, entry)),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(MediaKind? kind, String label) {
    final selected = _filter == kind;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => setState(() => _filter = kind),
        selectedColor: DuetColors.pink.withValues(alpha: 0.25),
        backgroundColor: DuetColors.surface,
        side: BorderSide(color: selected ? DuetColors.pink : DuetColors.outline),
      ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({required this.entry, required this.onTap});

  final HistoryEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final subtitle = [
      if (entry.finished)
        'Finished'
      else if (entry.durationMs != null)
        '${formatPosition(entry.positionMs)} / ${formatPosition(entry.durationMs!)}'
      else
        'Stopped at ${formatPosition(entry.positionMs)}',
      formatRelative(entry.lastPlayedAt),
      if (entry.togetherMs > 60000) '${formatSpan(entry.togetherMs)} together',
    ].join(' · ');

    return Material(
      color: DuetColors.surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  gradient: switch (entry.kind) {
                    MediaKind.video => DuetColors.movieGradient,
                    MediaKind.audio => DuetColors.musicGradient,
                    MediaKind.youtube => DuetColors.youtubeGradient,
                  },
                ),
                child: Text(entry.kind.emoji, style: const TextStyle(fontSize: 22)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(entry.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 3),
                    Text(subtitle, style: const TextStyle(color: DuetColors.textMuted, fontSize: 12)),
                    if (entry.durationMs != null && !entry.finished) ...[
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(value: entry.progress, minHeight: 3),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                entry.finished ? Icons.replay_rounded : Icons.play_arrow_rounded,
                color: DuetColors.pink,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
