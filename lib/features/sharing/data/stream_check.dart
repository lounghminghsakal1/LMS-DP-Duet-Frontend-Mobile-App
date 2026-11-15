import 'dart:math' as math;

import 'package:dio/dio.dart';

import '../../library/domain/fingerprint.dart';

/// Before streaming, make sure the shared copy really is the partner's file:
/// same total size and the same fingerprint (size + first 4 MiB). Catches an
/// upload that went wrong instead of showing a frozen first frame.
/// Pure Dart (used by the app and the end-to-end test).
Future<bool> verifySharedCopy({
  required String url,
  required String fingerprint,
  required int sizeBytes,
  Dio? http,
}) async {
  final dio = http ?? Dio(BaseOptions(connectTimeout: const Duration(seconds: 15), receiveTimeout: const Duration(minutes: 1)));
  final want = math.min(sizeBytes, kFingerprintHeadBytes);
  final response = await dio.get<List<int>>(
    url,
    options: Options(responseType: ResponseType.bytes, headers: {'Range': 'bytes=0-${want - 1}'}),
  );

  int? total;
  final contentRange = response.headers.value('content-range'); // "bytes 0-4194303/12268544"
  if (contentRange != null) {
    total = int.tryParse(contentRange.split('/').last);
  } else if (response.statusCode == 200) {
    total = int.tryParse(response.headers.value('content-length') ?? '');
  }
  if (total != null && total != sizeBytes) return false;

  final data = response.data ?? const <int>[];
  if (data.length < want) return false;
  return fingerprintOf(sizeBytes, data.length == want ? data : data.sublist(0, want)) == fingerprint;
}
