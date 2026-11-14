import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../domain/share_models.dart';
import 'chunked_reader.dart';
import 'share_repository.dart';

/// Uploads a file in parts straight to storage (S3) with signed URLs:
///  * 3 parts in flight at once, ~30 MB of memory at most
///  * every part retried with backoff (flaky mobile networks), expired links re-signed
///  * parts that are already stored are skipped, so an interrupted upload resumes
/// Pure Dart: used by the app and by the end-to-end test.
class ShareUploader {
  ShareUploader({required this.repository, Dio? http, this.concurrency = 3, this.maxAttempts = 6})
      // A plain client: signed URLs must not get our Authorization header.
      : _http = http ?? Dio(BaseOptions(connectTimeout: const Duration(seconds: 20)));

  final ShareRepository repository;
  final int concurrency;
  final int maxAttempts;
  final Dio _http;
  final _cancelToken = CancelToken();
  final _urls = <int, String>{};
  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  void cancel() {
    _cancelled = true;
    if (!_cancelToken.isCancelled) _cancelToken.cancel('cancelled');
  }

  /// Uploads [share] reading bytes from [openStream] and completes it.
  /// [onProgress] receives the total number of bytes stored so far.
  Future<ShareInfo> upload({
    required ShareInfo share,
    required Stream<List<int>> Function() openStream,
    List<UploadedPart> alreadyUploaded = const [],
    void Function(int uploadedBytes)? onProgress,
  }) async {
    final done = <int, String>{for (final p in alreadyUploaded) p.partNumber: p.etag};
    var confirmed = 0;
    for (final p in alreadyUploaded) {
      confirmed += p.size > 0 ? p.size : share.sizeOfPart(p.partNumber);
    }
    final inFlight = <int, int>{};
    void report() => onProgress?.call(confirmed + inFlight.values.fold(0, (a, b) => a + b));
    report();

    final reader = ChunkedReader(openStream());
    var nextPart = 1;
    var reading = Future<void>.value();

    // Reads the next part that still needs uploading. Reads are serialized because
    // the stream is sequential; uploads run in parallel.
    Future<(int, Uint8List)?> takeNextPart() {
      final completer = Completer<(int, Uint8List)?>();
      reading = reading.then((_) async {
        try {
          while (nextPart <= share.partCount && !_cancelled) {
            final number = nextPart++;
            final bytes = await reader.next(share.sizeOfPart(number));
            if (bytes == null || bytes.length != share.sizeOfPart(number)) {
              throw StateError('The file changed or ended early while sharing.');
            }
            if (done.containsKey(number)) continue; // stored by a previous attempt
            completer.complete((number, bytes));
            return;
          }
          completer.complete(null);
        } catch (error, stack) {
          completer.completeError(error, stack);
        }
      });
      return completer.future;
    }

    Future<void> worker() async {
      while (!_cancelled) {
        final next = await takeNextPart();
        if (next == null) return;
        final (number, bytes) = next;
        final etag = await _uploadPart(share, number, bytes, (sent) {
          inFlight[number] = sent;
          report();
        });
        inFlight.remove(number);
        done[number] = etag;
        confirmed += bytes.length;
        report();
      }
    }

    try {
      await Future.wait([for (var i = 0; i < concurrency; i++) worker()]);
    } finally {
      await reader.close();
    }
    if (_cancelled) throw const ShareCancelledException();

    final parts = [
      for (var n = 1; n <= share.partCount; n++) UploadedPart(partNumber: n, etag: done[n]!),
    ];
    return repository.complete(share.id, parts);
  }

  Future<String> _urlFor(ShareInfo share, int partNumber) async {
    final cached = _urls[partNumber];
    if (cached != null) return cached;
    // Sign a small batch ahead to save round trips.
    final batch = [
      for (var n = partNumber; n <= math.min(partNumber + 19, share.partCount); n++)
        if (!_urls.containsKey(n)) n,
    ];
    _urls.addAll(await repository.presignParts(share.id, batch));
    return _urls[partNumber]!;
  }

  Future<String> _uploadPart(ShareInfo share, int number, Uint8List bytes, void Function(int sent) onSent) async {
    var attempt = 0;
    while (true) {
      if (_cancelled) throw const ShareCancelledException();
      try {
        final url = await _urlFor(share, number);
        final response = await _http.put<void>(
          url,
          data: Stream<List<int>>.value(bytes),
          options: Options(
            headers: {
              Headers.contentLengthHeader: bytes.length,
              Headers.contentTypeHeader: 'application/octet-stream',
            },
            sendTimeout: const Duration(minutes: 5),
            receiveTimeout: const Duration(minutes: 2),
          ),
          cancelToken: _cancelToken,
          onSendProgress: (sent, _) => onSent(sent),
        );
        final etag = response.headers.value('etag');
        if (etag == null || etag.isEmpty) throw StateError('Storage did not confirm part $number.');
        return etag;
      } on DioException catch (error) {
        if (CancelToken.isCancel(error) || _cancelled) throw const ShareCancelledException();
        if (error.response?.statusCode == 403) _urls.remove(number); // link expired → sign again
        attempt++;
        onSent(0);
        if (attempt >= maxAttempts) rethrow;
        await Future<void>.delayed(Duration(seconds: math.min(30, 1 << attempt)));
      }
    }
  }
}
