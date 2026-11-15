/// 75_000 -> "1:15", 3_725_000 -> "1:02:05"
String formatPosition(int milliseconds) {
  final totalSeconds = (milliseconds / 1000).floor().clamp(0, 1 << 31);
  final hours = totalSeconds ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  final seconds = totalSeconds % 60;
  final ss = seconds.toString().padLeft(2, '0');
  if (hours > 0) {
    return '$hours:${minutes.toString().padLeft(2, '0')}:$ss';
  }
  return '$minutes:$ss';
}

/// 4_500_000 -> "1h 15m", 90_000 -> "1m", 20_000 -> "20s"
String formatSpan(int milliseconds) {
  final totalMinutes = milliseconds ~/ 60000;
  if (totalMinutes <= 0) return '${(milliseconds / 1000).round()}s';
  final hours = totalMinutes ~/ 60;
  final minutes = totalMinutes % 60;
  if (hours == 0) return '${minutes}m';
  if (minutes == 0) return '${hours}h';
  return '${hours}h ${minutes}m';
}

String formatBytes(int bytes) {
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  final digits = value >= 100 || unit == 0 ? 0 : 1;
  return '${value.toStringAsFixed(digits)} ${units[unit]}';
}

String formatRelative(DateTime time, {DateTime? now}) {
  final reference = now ?? DateTime.now();
  final diff = reference.difference(time);
  if (diff.inSeconds < 45) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays == 1) return 'yesterday';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  return '${time.day}/${time.month}/${time.year}';
}

String formatClock(DateTime time) {
  final local = time.toLocal();
  final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
  final minute = local.minute.toString().padLeft(2, '0');
  final suffix = local.hour < 12 ? 'AM' : 'PM';
  return '$hour:$minute $suffix';
}

/// Tidies a file name for display: "My_Song___Live(720p)_261105203112" → "My Song Live(720p)".
/// Underscores become spaces and long timestamp numbers added by trimmer/recorder apps are dropped.
String prettyTitle(String raw) {
  var title = raw.replaceAll('_', ' ');
  title = title.replaceAll(RegExp(r'(^|\s)\d{10,}(?=\s|$)'), ' ');
  title = title.replaceAll(RegExp(r'\s{2,}'), ' ').trim();
  return title.isEmpty ? raw.trim() : title;
}
