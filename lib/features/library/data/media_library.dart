import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path/path.dart' as p;
import 'package:photo_manager/photo_manager.dart';

import '../../../core/utils/format.dart';
import '../../history/data/history_store.dart';
import '../../history/presentation/history_controller.dart';
import '../../session/domain/room_state.dart';
import '../domain/fingerprint.dart';
import '../domain/local_media.dart';

/// Finds movies and songs that are already on the phone. Nothing is copied or
/// uploaded: files are played straight from where they are.
class MediaLibrary {
  MediaLibrary(this._history);

  final HistoryStore _history;

  /// Files picked with the system picker this session (content:// uris can only be
  /// read through the picked handle, e.g. to share them with the partner).
  final _picked = <String, PlatformFile>{};

  /// Reads the file's bytes, from a path or a content:// uri picked earlier.
  Stream<List<int>> openRead(LocalMedia media) {
    if (!media.isContentUri) return File(media.source).openRead();
    final picked = _picked[media.source];
    if (picked == null) {
      throw const FileSystemException('Pick the file again so Duet can read it.');
    }
    return picked.readAsByteStream();
  }

  /// True if [openRead] will work for this file right now.
  bool canRead(LocalMedia media) => !media.isContentUri || _picked.containsKey(media.source);

  RequestType _type(MediaKind kind) => kind == MediaKind.audio ? RequestType.audio : RequestType.video;

  FilterOptionGroup _filter({int? durationMs}) {
    final duration = durationMs != null && durationMs > 0
        ? DurationConstraint(
            min: Duration(milliseconds: (durationMs - 3000).clamp(0, durationMs)),
            max: Duration(milliseconds: durationMs + 3000),
          )
        : const DurationConstraint(max: Duration(days: 2), allowNullable: true);
    final option = FilterOption(needTitle: true, durationConstraint: duration);
    return FilterOptionGroup(
      videoOption: option,
      audioOption: option,
      orders: const [OrderOption(type: OrderOptionType.createDate, asc: false)],
    );
  }

  Future<bool> requestAccess(MediaKind kind) async {
    final state = await PhotoManager.requestPermissionExtend(
      requestOption: PermissionRequestOption(
        androidPermission: AndroidPermission(type: _type(kind), mediaLocation: false),
      ),
    );
    return state.hasAccess;
  }

  Future<void> openSettings() => PhotoManager.openSetting();

  Future<int> count(MediaKind kind) => PhotoManager.getAssetCount(type: _type(kind), filterOption: _filter());

  Future<List<AssetEntity>> page(MediaKind kind, int page, {int size = 60}) {
    return PhotoManager.getAssetListPaged(
      page: page,
      pageCount: size,
      type: _type(kind),
      filterOption: _filter(),
    );
  }

  /// Turns a library item into a playable [LocalMedia] (computes the fingerprint).
  Future<LocalMedia> prepareAsset(AssetEntity asset, MediaKind kind) async {
    final file = await asset.originFile ?? await asset.file;
    if (file == null) throw const FileSystemException('This file is not available on the device.');
    final fp = await fingerprintFile(file.path);
    final title = asset.title?.isNotEmpty == true ? asset.title! : p.basename(file.path);
    return LocalMedia(
      kind: kind,
      source: file.path,
      title: _cleanTitle(title),
      sizeBytes: fp.sizeBytes,
      fingerprint: fp.fingerprint,
      durationMs: asset.duration > 0 ? asset.duration * 1000 : null,
      fileName: p.basename(file.path),
    );
  }

  /// Opens the system file picker (works for files outside the media library,
  /// e.g. Downloads or SD card). On Android this returns a content:// uri, so
  /// even a huge movie is not copied.
  Future<LocalMedia?> pickFromFiles(MediaKind kind) async {
    final picked = await FilePicker.pickFile(type: kind == MediaKind.audio ? FileType.audio : FileType.video);
    if (picked == null) return null;
    final path = picked.path;
    if (path != null) {
      final fp = await fingerprintFile(path);
      return LocalMedia(
        kind: kind,
        source: path,
        title: _cleanTitle(picked.name),
        sizeBytes: fp.sizeBytes,
        fingerprint: fp.fingerprint,
        fileName: picked.name,
      );
    }
    final size = picked.lengthSync() ?? await picked.length() ?? 0;
    final fingerprint = await fingerprintStream(picked.readAsByteStream(), size);
    final source = picked.uri.toString();
    _picked[source] = picked;
    return LocalMedia(
      kind: kind,
      source: source,
      title: _cleanTitle(picked.name),
      sizeBytes: size,
      fingerprint: fingerprint,
      fileName: picked.name,
    );
  }

  /// Re-opens a file we played before (from history). Returns null if it moved
  /// or the app lost access to it.
  Future<LocalMedia?> fromSource(String source, MediaKind kind, String title) async {
    if (source.startsWith('content://')) return null; // access to picked uris does not survive restarts
    final file = File(source);
    if (!await file.exists()) return null;
    try {
      final fp = await fingerprintFile(source);
      return LocalMedia(
        kind: kind,
        source: source,
        title: title,
        sizeBytes: fp.sizeBytes,
        fingerprint: fp.fingerprint,
        fileName: p.basename(source),
      );
    } catch (_) {
      return null;
    }
  }

  /// Looks for the exact file the partner is playing:
  ///   1. where we found it last time (history),
  ///   2. library items with the same duration, then the same size and fingerprint,
  ///   3. every library item with the same size.
  Future<LocalMedia?> autoFind(RoomMedia target, {void Function(String status)? onProgress}) async {
    final fingerprint = target.fingerprint;
    if (fingerprint == null) return null;

    final remembered = _history.get(fingerprint);
    if (remembered?.source != null) {
      onProgress?.call('Checking where you played it last time…');
      final media = await fromSource(remembered!.source!, target.kind, remembered.title);
      if (media != null && media.fingerprint == fingerprint) return media;
    }

    if (!await requestAccess(target.kind)) return null;

    final checked = <String>{};
    Future<LocalMedia?> scan(FilterOptionGroup filter, String status) async {
      onProgress?.call(status);
      final type = _type(target.kind);
      final total = await PhotoManager.getAssetCount(type: type, filterOption: filter);
      const pageSize = 100;
      for (var page = 0; page * pageSize < total && page < 40; page++) {
        final assets = await PhotoManager.getAssetListPaged(
          page: page,
          pageCount: pageSize,
          type: type,
          filterOption: filter,
        );
        for (final asset in assets) {
          if (!checked.add(asset.id)) continue;
          final file = await asset.originFile;
          if (file == null) continue;
          final size = await file.length();
          if (target.sizeBytes != null && size != target.sizeBytes) continue;
          final fp = await fingerprintFile(file.path);
          if (fp.fingerprint == fingerprint) {
            final title = asset.title?.isNotEmpty == true ? asset.title! : p.basename(file.path);
            return LocalMedia(
              kind: target.kind,
              source: file.path,
              title: _cleanTitle(title),
              sizeBytes: fp.sizeBytes,
              fingerprint: fp.fingerprint,
              durationMs: asset.duration > 0 ? asset.duration * 1000 : target.durationMs,
              fileName: p.basename(file.path),
            );
          }
        }
      }
      return null;
    }

    if (target.durationMs != null && target.durationMs! > 0) {
      final byDuration = await scan(_filter(durationMs: target.durationMs), 'Looking for a file with the same length…');
      if (byDuration != null) return byDuration;
    }
    return scan(_filter(), 'Checking the rest of your library…');
  }

  /// Reads a file's length with the player engine (for files picked without metadata).
  Future<int?> probeDurationMs(String source) async {
    final player = Player();
    try {
      await player.setVolume(0);
      await player.open(Media(source), play: false);
      final duration = player.state.duration > Duration.zero
          ? player.state.duration
          : await player.stream.duration
              .firstWhere((d) => d > Duration.zero)
              .timeout(const Duration(seconds: 6), onTimeout: () => Duration.zero);
      return duration > Duration.zero ? duration.inMilliseconds : null;
    } catch (_) {
      return null;
    } finally {
      await player.dispose();
    }
  }

  static String _cleanTitle(String name) {
    final withoutExt = p.basenameWithoutExtension(name);
    return prettyTitle(withoutExt.isEmpty ? name : withoutExt);
  }
}

final mediaLibraryProvider = Provider<MediaLibrary>((ref) => MediaLibrary(ref.watch(historyStoreProvider)));
