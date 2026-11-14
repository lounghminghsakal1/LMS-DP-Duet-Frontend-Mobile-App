import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../domain/share_models.dart';

/// REST calls for temporary sharing. Pure Dart (no Flutter) so tests can use it.
class ShareRepository {
  ShareRepository(this._dio);

  final Dio _dio;

  /// Starts or resumes the upload of the movie that is open in the room.
  Future<({ShareInfo share, List<UploadedPart> uploaded})> create({
    required String fingerprint,
    required String title,
    required String kind,
    required int sizeBytes,
    String? fileName,
  }) =>
      guardApi(() async {
        final res = await _dio.post<Map<String, dynamic>>('/shares', data: {
          'fingerprint': fingerprint,
          'title': title,
          'kind': kind,
          'sizeBytes': sizeBytes,
          if (fileName != null) ...{'fileName': fileName, 'mimeType': mimeTypeFor(fileName)},
        });
        final data = res.data!;
        return (
          share: ShareInfo.fromJson(data['share'] as Map<String, dynamic>),
          uploaded: [
            for (final p in (data['uploadedParts'] as List? ?? const []))
              UploadedPart.fromJson(p as Map<String, dynamic>),
          ],
        );
      });

  /// Signed upload URLs for these part numbers (max 50 per call).
  Future<Map<int, String>> presignParts(String shareId, List<int> partNumbers) => guardApi(() async {
        final res = await _dio.post<Map<String, dynamic>>(
          '/shares/$shareId/parts',
          data: {'partNumbers': partNumbers},
        );
        final urls = res.data!['urls'] as Map<String, dynamic>;
        return {for (final e in urls.entries) int.parse(e.key): e.value as String};
      });

  Future<ShareInfo> complete(String shareId, List<UploadedPart> parts) => guardApi(() async {
        final res = await _dio.post<Map<String, dynamic>>(
          '/shares/$shareId/complete',
          data: {'parts': [for (final p in parts) p.toJson()]},
        );
        return ShareInfo.fromJson(res.data!['share'] as Map<String, dynamic>);
      });

  /// A time-limited streaming link for the partner's player.
  Future<({String url, DateTime expiresAt})> streamUrl(String shareId) => guardApi(() async {
        final res = await _dio.get<Map<String, dynamic>>('/shares/$shareId/stream');
        final data = res.data!;
        return (
          url: data['url'] as String,
          expiresAt: DateTime.tryParse(data['expiresAt'] as String? ?? '') ?? DateTime.now(),
        );
      });

  Future<void> cancel(String shareId) => guardApi(() async {
        await _dio.delete<void>('/shares/$shareId');
      });
}

final shareRepositoryProvider = Provider<ShareRepository>((ref) => ShareRepository(ref.watch(dioProvider)));
