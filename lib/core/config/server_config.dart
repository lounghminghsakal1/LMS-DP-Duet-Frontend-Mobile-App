import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../storage/prefs.dart';

/// Default backend address. Override at build time:
///   flutter run --dart-define=API_BASE_URL=http://192.168.1.26:4747
/// 10.0.2.2 is "localhost of the computer" as seen from the Android emulator.
const String kDefaultServerUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: "http://192.168.1.37:4747"
  // defaultValue: 'http://10.0.2.2:4747',
);

/// Adds a scheme if missing and strips trailing slashes.
String normalizeServerUrl(String input) {
  var value = input.trim();
  if (value.isEmpty) return kDefaultServerUrl;
  if (!value.startsWith('http://') && !value.startsWith('https://')) {
    value = 'http://$value';
  }
  while (value.endsWith('/')) {
    value = value.substring(0, value.length - 1);
  }
  return value;
}

/// http://host:port -> ws://host:port/ws  (https -> wss)
Uri webSocketUriFor(String httpBase) {
  final uri = Uri.parse(httpBase);
  final basePath = uri.path.endsWith('/') ? uri.path.substring(0, uri.path.length - 1) : uri.path;
  return uri.replace(scheme: uri.scheme == 'https' ? 'wss' : 'ws', path: '$basePath/ws');
}

/// The server URL is editable from the sign-in screen so both phones can point
/// at a laptop on the same Wi-Fi or at a deployed server without rebuilding.
class ServerUrlNotifier extends Notifier<String> {
  static const _prefsKey = 'server_url';

  @override
  String build() {
    final saved = ref.read(sharedPreferencesProvider).getString(_prefsKey);
    return saved ?? kDefaultServerUrl;
  }

  Future<void> set(String url) async {
    final normalized = normalizeServerUrl(url);
    await ref.read(sharedPreferencesProvider).setString(_prefsKey, normalized);
    state = normalized;
  }

  Future<void> reset() async {
    await ref.read(sharedPreferencesProvider).remove(_prefsKey);
    state = kDefaultServerUrl;
  }
}

final serverUrlProvider = NotifierProvider<ServerUrlNotifier, String>(ServerUrlNotifier.new);
