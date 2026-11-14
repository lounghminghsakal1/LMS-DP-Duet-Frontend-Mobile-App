import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// How much of the file is hashed. The size plus the first 4 MiB identifies a
/// file reliably (different encodes/releases differ in size and header) and is
/// fast even for a 10 GB movie. Only the beginning is read so the same
/// fingerprint can be computed from a plain path or an Android content:// stream.
const kFingerprintHeadBytes = 4 * 1024 * 1024;

String fingerprintOf(int sizeBytes, List<int> head) {
  final output = _DigestSink();
  final input = sha256.startChunkedConversion(output);
  input.add(utf8.encode('duet-v1:$sizeBytes:'));
  input.add(head);
  input.close();
  return output.value!.toString();
}

/// Fingerprint of a file on disk (runs off the UI thread).
Future<({String fingerprint, int sizeBytes})> fingerprintFile(String path) {
  return Isolate.run(() async {
    final file = await File(path).open();
    try {
      final size = await file.length();
      final head = await file.read(size < kFingerprintHeadBytes ? size : kFingerprintHeadBytes);
      return (fingerprint: fingerprintOf(size, head), sizeBytes: size);
    } finally {
      await file.close();
    }
  });
}

/// Fingerprint from a byte stream (e.g. an Android content:// uri). Only the
/// first [kFingerprintHeadBytes] are read, then the stream is cancelled.
Future<String> fingerprintStream(Stream<List<int>> stream, int sizeBytes) async {
  final head = await readHead(stream, kFingerprintHeadBytes);
  return Isolate.run(() => fingerprintOf(sizeBytes, head));
}

Future<Uint8List> readHead(Stream<List<int>> stream, int maxBytes) async {
  final builder = BytesBuilder(copy: false);
  await for (final chunk in stream) {
    final remaining = maxBytes - builder.length;
    if (chunk.length >= remaining) {
      builder.add(chunk.sublist(0, remaining));
      break;
    }
    builder.add(chunk);
  }
  return builder.takeBytes();
}

class _DigestSink implements Sink<Digest> {
  Digest? value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}
