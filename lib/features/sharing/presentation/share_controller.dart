import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../library/data/media_library.dart';
import '../../library/domain/local_media.dart';
import '../../session/domain/room_state.dart';
import '../../session/presentation/session_controller.dart';
import '../data/share_repository.dart';
import '../data/share_uploader.dart';
import '../domain/share_models.dart';

/// The local file open in the watch screen right now (so sharing can reuse it).
class ActiveLocalMedia extends Notifier<LocalMedia?> {
  @override
  LocalMedia? build() => null;

  void set(LocalMedia? media) => state = media;

  /// Clears it only if it is still [media] (a newer screen may have replaced it).
  void clearIf(LocalMedia? media) {
    if (identical(state, media)) state = null;
  }
}

final activeLocalMediaProvider = NotifierProvider<ActiveLocalMedia, LocalMedia?>(ActiveLocalMedia.new);

enum ShareUploadStatus { idle, preparing, uploading, finishing, done, failed, cancelled }

class ShareUploadState {
  const ShareUploadState({
    this.status = ShareUploadStatus.idle,
    this.title,
    this.fingerprint,
    this.shareId,
    this.uploadedBytes = 0,
    this.sizeBytes = 0,
    this.error,
  });

  final ShareUploadStatus status;
  final String? title;
  final String? fingerprint;
  final String? shareId;
  final int uploadedBytes;
  final int sizeBytes;
  final String? error;

  bool get isBusy =>
      status == ShareUploadStatus.preparing ||
      status == ShareUploadStatus.uploading ||
      status == ShareUploadStatus.finishing;
  double get progress => sizeBytes <= 0 ? 0 : (uploadedBytes / sizeBytes).clamp(0, 1).toDouble();

  ShareUploadState copyWith({
    ShareUploadStatus? status,
    String? shareId,
    int? uploadedBytes,
    int? sizeBytes,
    String? error,
  }) =>
      ShareUploadState(
        status: status ?? this.status,
        title: title,
        fingerprint: fingerprint,
        shareId: shareId ?? this.shareId,
        uploadedBytes: uploadedBytes ?? this.uploadedBytes,
        sizeBytes: sizeBytes ?? this.sizeBytes,
        error: error ?? this.error,
      );
}

/// Uploads the current movie so the partner (who doesn't have it) can stream it.
/// Lives app-wide, so the upload continues while you move between screens.
class ShareController extends Notifier<ShareUploadState> {
  ShareUploader? _uploader;
  int _lastReportMs = 0;

  @override
  ShareUploadState build() {
    ref.watch(currentUserIdProvider);
    // A different movie (or none) → this upload is pointless: stop it.
    ref.listen(sessionControllerProvider.select((s) => s.media?.fingerprint), (_, fingerprint) {
      if (state.isBusy && fingerprint != state.fingerprint) cancel();
    });
    ref.onDispose(() => _uploader?.cancel());
    return const ShareUploadState();
  }

  /// Finds this phone's copy of the room's movie and uploads it.
  Future<void> shareCurrent() async {
    if (state.isBusy) return;
    final session = ref.read(sessionControllerProvider);
    final media = session.media;
    final client = ref.read(sessionControllerProvider.notifier).client;
    if (media == null || media.kind == MediaKind.youtube || media.fingerprint == null || client == null) return;

    state = ShareUploadState(
      status: ShareUploadStatus.preparing,
      title: media.title,
      fingerprint: media.fingerprint,
      sizeBytes: media.sizeBytes ?? 0,
    );

    try {
      final local = await _findLocal(media);
      if (local == null) {
        state = state.copyWith(
          status: ShareUploadStatus.failed,
          error: "Couldn't find “${media.title}” on your phone to share.",
        );
        client.declineShare();
        return;
      }

      final repository = ref.read(shareRepositoryProvider);
      final created = await repository.create(
        fingerprint: local.fingerprint,
        title: media.title,
        kind: media.kind.name,
        sizeBytes: local.sizeBytes,
        fileName: local.fileName,
      );
      if (created.share.isReady) {
        state = state.copyWith(status: ShareUploadStatus.done, shareId: created.share.id, uploadedBytes: local.sizeBytes);
        return;
      }

      state = state.copyWith(
        status: ShareUploadStatus.uploading,
        shareId: created.share.id,
        sizeBytes: local.sizeBytes,
      );
      final library = ref.read(mediaLibraryProvider);
      final uploader = ShareUploader(repository: repository);
      _uploader = uploader;
      await uploader.upload(
        share: created.share,
        alreadyUploaded: created.uploaded,
        openStream: () => library.openRead(local),
        onProgress: (bytes) => _onProgress(created.share.id, bytes),
      );
      if (!ref.mounted) return;
      state = state.copyWith(status: ShareUploadStatus.done, uploadedBytes: local.sizeBytes);
    } on ShareCancelledException {
      if (ref.mounted) state = state.copyWith(status: ShareUploadStatus.cancelled);
    } on ApiException catch (error) {
      if (ref.mounted) state = state.copyWith(status: ShareUploadStatus.failed, error: error.message);
    } catch (error) {
      if (ref.mounted) {
        state = state.copyWith(status: ShareUploadStatus.failed, error: 'Sharing failed: $error');
      }
    } finally {
      _uploader = null;
    }
  }

  /// Stops uploading and deletes whatever was uploaded so far.
  Future<void> cancel() async {
    _uploader?.cancel();
    final shareId = state.shareId;
    if (shareId != null) {
      try {
        await ref.read(shareRepositoryProvider).cancel(shareId);
      } catch (_) {}
    }
    if (ref.mounted) state = state.copyWith(status: ShareUploadStatus.cancelled);
  }

  void _onProgress(String shareId, int bytes) {
    if (!ref.mounted) return;
    state = state.copyWith(uploadedBytes: bytes);
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastReportMs >= 1000) {
      _lastReportMs = now;
      ref.read(sessionControllerProvider.notifier).client?.reportShareProgress(shareId, bytes);
    }
  }

  Future<LocalMedia?> _findLocal(RoomMedia media) async {
    final library = ref.read(mediaLibraryProvider);
    final active = ref.read(activeLocalMediaProvider);
    if (active != null && !active.isStreamed && active.fingerprint == media.fingerprint && library.canRead(active)) {
      return active;
    }
    final found = await library.autoFind(media);
    return found != null && library.canRead(found) ? found : null;
  }
}

final shareControllerProvider = NotifierProvider<ShareController, ShareUploadState>(ShareController.new);
