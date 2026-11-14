import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photo_manager/photo_manager.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/format.dart';
import '../../../core/widgets/common.dart';
import '../../session/domain/room_state.dart';
import '../data/media_library.dart';
import '../domain/local_media.dart';

/// Lists the movies or songs already on the phone. Pops with a [LocalMedia].
class MediaPickerScreen extends ConsumerStatefulWidget {
  const MediaPickerScreen({super.key, required this.kind, this.hint});

  final MediaKind kind;

  /// e.g. "Pick “Inception” (2.1 GB)" when joining the partner.
  final String? hint;

  @override
  ConsumerState<MediaPickerScreen> createState() => _MediaPickerScreenState();
}

class _MediaPickerScreenState extends ConsumerState<MediaPickerScreen> {
  static const _pageSize = 60;

  final _assets = <AssetEntity>[];
  final _thumbs = <String, Future<Uint8List?>>{};
  final _scroll = ScrollController();
  bool _loading = true;
  bool _loadingMore = false;
  bool _denied = false;
  bool _preparing = false;
  int _total = 0;
  int _page = 0;
  String _query = '';

  MediaLibrary get _library => ref.read(mediaLibraryProvider);
  bool get _isAudio => widget.kind == MediaKind.audio;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 400) _loadMore();
    });
    _init();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    setState(() {
      _loading = true;
      _denied = false;
    });
    try {
      final granted = await _library.requestAccess(widget.kind);
      if (!granted) {
        setState(() {
          _denied = true;
          _loading = false;
        });
        return;
      }
      _total = await _library.count(widget.kind);
      final first = await _library.page(widget.kind, 0, size: _pageSize);
      if (!mounted) return;
      setState(() {
        _assets
          ..clear()
          ..addAll(first);
        _page = 1;
        _loading = false;
      });
    } catch (_) {
      // Library not available (e.g. unsupported platform) – the file picker still works.
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _assets.length >= _total) return;
    _loadingMore = true;
    try {
      final next = await _library.page(widget.kind, _page, size: _pageSize);
      if (!mounted) return;
      setState(() {
        _assets.addAll(next);
        _page++;
      });
    } finally {
      _loadingMore = false;
    }
  }

  Future<void> _choose(Future<LocalMedia?> Function() prepare) async {
    setState(() => _preparing = true);
    try {
      final media = await prepare();
      if (!mounted) return;
      if (media != null) Navigator.of(context).pop(media);
    } catch (error) {
      if (mounted) showToast(context, "Couldn't open that file: $error", icon: Icons.error_outline_rounded);
    } finally {
      if (mounted) setState(() => _preparing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final visible = _query.isEmpty
        ? _assets
        : _assets.where((a) => (a.title ?? '').toLowerCase().contains(_query.toLowerCase())).toList();

    return Scaffold(
      appBar: AppBar(title: Text(_isAudio ? 'Choose a song' : 'Choose a movie')),
      body: DuetBackground(
        child: Stack(
          children: [
            Column(
              children: [
                if (widget.hint != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: context.palette.accent2.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: context.palette.accent2.withValues(alpha: 0.4)),
                      ),
                      child: Text(widget.hint!, style: const TextStyle(fontWeight: FontWeight.w600)),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          onChanged: (v) => setState(() => _query = v),
                          decoration: const InputDecoration(
                            hintText: 'Search',
                            prefixIcon: Icon(Icons.search_rounded),
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      FilledButton.tonalIcon(
                        style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
                        onPressed: _preparing ? null : () => _choose(() => _library.pickFromFiles(widget.kind)),
                        icon: const Icon(Icons.folder_open_rounded),
                        label: const Text('Files'),
                      ),
                    ],
                  ),
                ),
                Expanded(child: _buildBody(visible)),
              ],
            ),
            if (_preparing)
              Container(
                color: Colors.black54,
                alignment: Alignment.center,
                child: const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 14),
                    Text('Getting it ready…', style: TextStyle(fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(List<AssetEntity> visible) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_denied) {
      return _Message(
        emoji: '🔒',
        title: 'Duet needs access to your ${_isAudio ? 'music' : 'videos'}',
        body: 'Files are played straight from your phone. Nothing is uploaded.',
        action: FilledButton(
          onPressed: () async {
            await _library.openSettings();
            _init();
          },
          child: const Text('Open settings'),
        ),
      );
    }
    if (visible.isEmpty) {
      return _Message(
        emoji: _isAudio ? '🎵' : '🎬',
        title: _query.isEmpty ? 'Nothing found in your library' : 'No matches',
        body: 'Use “Files” to pick from Downloads, an SD card or any folder.',
      );
    }
    return ListView.separated(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      itemCount: visible.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final asset = visible[index];
        return _AssetTile(
          asset: asset,
          isAudio: _isAudio,
          thumbnail: _isAudio
              ? null
              : _thumbs.putIfAbsent(asset.id, () => asset.thumbnailDataWithSize(const ThumbnailSize(320, 180))),
          onTap: _preparing ? null : () => _choose(() => _library.prepareAsset(asset, widget.kind)),
        );
      },
    );
  }
}

class _AssetTile extends StatelessWidget {
  const _AssetTile({required this.asset, required this.isAudio, required this.onTap, this.thumbnail});

  final AssetEntity asset;
  final bool isAudio;
  final Future<Uint8List?>? thumbnail;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final title = asset.title ?? 'Untitled';
    return Material(
      color: context.palette.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: isAudio ? 52 : 96,
                  height: 54,
                  child: isAudio
                      ? DecoratedBox(
                          decoration: BoxDecoration(gradient: context.palette.musicGradient),
                          child: Icon(Icons.music_note_rounded, color: Colors.white),
                        )
                      : FutureBuilder<Uint8List?>(
                          future: thumbnail,
                          builder: (context, snap) => snap.data == null
                              ? ColoredBox(
                                  color: context.palette.surfaceHigh,
                                  child: Icon(Icons.movie_rounded, color: DuetColors.textFaint),
                                )
                              : Image.memory(snap.data!, fit: BoxFit.cover, gaplessPlayback: true),
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Text(
                      [
                        if (asset.duration > 0) formatPosition(asset.duration * 1000),
                        if (asset.relativePath != null) asset.relativePath!.replaceAll(RegExp(r'/$'), ''),
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: DuetColors.textMuted, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: DuetColors.textFaint),
            ],
          ),
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.emoji, required this.title, required this.body, this.action});

  final String emoji;
  final String title;
  final String body;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 44)),
            const SizedBox(height: 12),
            Text(title, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(body, textAlign: TextAlign.center, style: const TextStyle(color: DuetColors.textMuted)),
            if (action != null) ...[const SizedBox(height: 18), action!],
          ],
        ),
      ),
    );
  }
}
