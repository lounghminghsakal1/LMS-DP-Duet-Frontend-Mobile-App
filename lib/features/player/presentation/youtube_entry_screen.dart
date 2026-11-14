import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common.dart';
import '../../history/presentation/history_controller.dart';
import '../../session/domain/room_state.dart';
import '../data/youtube_sync_player.dart';
import 'watch_flow.dart';

/// Paste a YouTube link, see a preview, start it for both.
class YoutubeEntryScreen extends ConsumerStatefulWidget {
  const YoutubeEntryScreen({super.key});

  @override
  ConsumerState<YoutubeEntryScreen> createState() => _YoutubeEntryScreenState();
}

class _YoutubeEntryScreenState extends ConsumerState<YoutubeEntryScreen> {
  final _controller = TextEditingController();
  String? _videoId;
  String? _title;
  String? _author;
  bool _loadingPreview = false;

  @override
  void initState() {
    super.initState();
    _pasteFromClipboardIfLink();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _pasteFromClipboardIfLink() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text != null && parseYoutubeId(text) != null && mounted && _controller.text.isEmpty) {
      _controller.text = text.trim();
      _onChanged(_controller.text);
    }
  }

  Future<void> _onChanged(String value) async {
    final id = parseYoutubeId(value);
    if (id == _videoId) return;
    setState(() {
      _videoId = id;
      _title = null;
      _author = null;
    });
    if (id == null) return;
    setState(() => _loadingPreview = true);
    // oEmbed gives the title without an API key.
    try {
      final res = await Dio(BaseOptions(connectTimeout: const Duration(seconds: 6))).get<Map<String, dynamic>>(
        'https://www.youtube.com/oembed',
        queryParameters: {'url': 'https://www.youtube.com/watch?v=$id', 'format': 'json'},
      );
      if (!mounted || _videoId != id) return;
      setState(() {
        _title = res.data?['title'] as String?;
        _author = res.data?['author_name'] as String?;
      });
    } catch (_) {
      // Private / age-restricted videos have no oEmbed; we can still try to play.
    } finally {
      if (mounted) setState(() => _loadingPreview = false);
    }
  }

  void _start() {
    final id = _videoId;
    if (id == null) return;
    WatchFlow.startYoutube(context, ref, videoId: id, title: _title ?? 'YouTube video');
  }

  @override
  Widget build(BuildContext context) {
    final recent = ref
        .watch(historyControllerProvider)
        .where((e) => e.kind == MediaKind.youtube && e.youtubeId != null)
        .take(8)
        .toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Watch YouTube together')),
      body: DuetBackground(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            TextField(
              controller: _controller,
              onChanged: _onChanged,
              autocorrect: false,
              keyboardType: TextInputType.url,
              decoration: InputDecoration(
                hintText: 'Paste a YouTube link',
                prefixIcon: const Icon(Icons.link_rounded),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.content_paste_rounded),
                  onPressed: () async {
                    final data = await Clipboard.getData(Clipboard.kTextPlain);
                    if (data?.text != null) {
                      _controller.text = data!.text!.trim();
                      _onChanged(_controller.text);
                    }
                  },
                ),
              ),
            ),
            const SizedBox(height: 20),
            if (_videoId != null) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Image.network(
                    'https://i.ytimg.com/vi/$_videoId/hqdefault.jpg',
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const ColoredBox(color: DuetColors.surfaceHigh),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (_loadingPreview)
                const LinearProgressIndicator()
              else ...[
                Text(_title ?? 'YouTube video', style: Theme.of(context).textTheme.titleMedium),
                if (_author != null)
                  Text(_author!, style: const TextStyle(color: DuetColors.textMuted)),
              ],
              const SizedBox(height: 20),
              GradientButton(
                label: 'Watch together',
                icon: Icons.play_arrow_rounded,
                gradient: DuetColors.youtubeGradient,
                onPressed: _start,
              ),
            ] else
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  'Copy a link from the YouTube app (Share → Copy link) and paste it here. '
                  'You both watch the same video in sync and can chat while it plays.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: DuetColors.textMuted, height: 1.4),
                ),
              ),
            if (recent.isNotEmpty) ...[
              const SizedBox(height: 28),
              const SectionTitle('Recently watched'),
              for (final entry in recent)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      'https://i.ytimg.com/vi/${entry.youtubeId}/mqdefault.jpg',
                      width: 80,
                      height: 45,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const SizedBox(width: 80, height: 45),
                    ),
                  ),
                  title: Text(entry.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: entry.durationMs == null
                      ? null
                      : LinearProgressIndicator(value: entry.progress, minHeight: 3),
                  onTap: () => WatchFlow.startYoutube(context, ref, videoId: entry.youtubeId!, title: entry.title),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
