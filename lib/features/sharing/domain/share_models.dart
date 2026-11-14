/// A temporary upload on the server (see backend shares.service.js).
class ShareInfo {
  const ShareInfo({
    required this.id,
    required this.fingerprint,
    required this.title,
    required this.kind,
    required this.sizeBytes,
    required this.partSize,
    required this.partCount,
    required this.status,
    this.uploaderId,
  });

  final String id;
  final String fingerprint;
  final String title;
  final String kind;
  final int sizeBytes;
  final int partSize;
  final int partCount;

  /// uploading | ready | deleted
  final String status;
  final String? uploaderId;

  bool get isReady => status == 'ready';

  /// Byte length of part [partNumber] (1-based); the last part is shorter.
  int sizeOfPart(int partNumber) =>
      partNumber < partCount ? partSize : sizeBytes - partSize * (partCount - 1);

  factory ShareInfo.fromJson(Map<String, dynamic> json) => ShareInfo(
        id: json['id'] as String,
        fingerprint: json['fingerprint'] as String,
        title: json['title'] as String,
        kind: json['kind'] as String,
        sizeBytes: (json['sizeBytes'] as num).toInt(),
        partSize: (json['partSize'] as num).toInt(),
        partCount: (json['partCount'] as num).toInt(),
        status: json['status'] as String,
        uploaderId: json['uploaderId'] as String?,
      );
}

/// A part that is already stored (from a previous, interrupted attempt or this one).
class UploadedPart {
  const UploadedPart({required this.partNumber, required this.etag, this.size = 0});

  final int partNumber;
  final String etag;
  final int size;

  factory UploadedPart.fromJson(Map<String, dynamic> json) => UploadedPart(
        partNumber: (json['partNumber'] as num).toInt(),
        etag: json['etag'] as String,
        size: (json['size'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toJson() => {'partNumber': partNumber, 'etag': etag};
}

class ShareCancelledException implements Exception {
  const ShareCancelledException();

  @override
  String toString() => 'Sharing was cancelled.';
}

/// Common file extensions → MIME types for the upload.
String mimeTypeFor(String fileName) {
  final ext = fileName.contains('.') ? fileName.split('.').last.toLowerCase() : '';
  return switch (ext) {
    'mp4' || 'm4v' => 'video/mp4',
    'mkv' => 'video/x-matroska',
    'webm' => 'video/webm',
    'mov' => 'video/quicktime',
    'avi' => 'video/x-msvideo',
    'ts' => 'video/mp2t',
    '3gp' => 'video/3gpp',
    'mp3' => 'audio/mpeg',
    'm4a' || 'aac' => 'audio/mp4',
    'flac' => 'audio/flac',
    'wav' => 'audio/wav',
    'ogg' || 'opus' => 'audio/ogg',
    _ => 'application/octet-stream',
  };
}
