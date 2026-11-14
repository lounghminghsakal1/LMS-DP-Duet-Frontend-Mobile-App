import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../storage/prefs.dart';

/// Optional build-time override: flutter run --dart-define=API_BASE_URL=http://192.168.1.37:4747
const String _dartDefineServerUrl = String.fromEnvironment('API_BASE_URL');

/// Used only if neither --dart-define nor .env provide a value.
/// 10.0.2.2 is "localhost of the computer" as seen from the Android emulator.
const String _fallbackServerUrl = 'http://10.0.2.2:4747';

/// Default backend address: --dart-define → `.env` (API_BASE_URL) → emulator fallback.
///
/// NOTE: the app's `.env` is bundled inside the APK, so it must only hold
/// non-secret config like this URL — never passwords or AWS keys.
String get kDefaultServerUrl {
  if (_dartDefineServerUrl.isNotEmpty) return _clean(_dartDefineServerUrl);
  final fromEnv = dotenv.isInitialized ? dotenv.maybeGet('API_BASE_URL')?.trim() : null;
  if (fromEnv != null && fromEnv.isNotEmpty) return _clean(fromEnv);
  return _fallbackServerUrl;
}

String _clean(String value) {
  var url = value.trim();
  if (!url.startsWith('http://') && !url.startsWith('https://')) url = 'http://$url';
  while (url.endsWith('/')) {
    url = url.substring(0, url.length - 1);
  }
  return url;
}

/// Adds a scheme if missing and strips trailing slashes.
String normalizeServerUrl(String input) {
  if (input.trim().isEmpty) return kDefaultServerUrl;
  return _clean(input);
}

/// http://host:port -> ws://host:port/api/ws  (https -> wss).
/// Everything is under /api so a reverse proxy needs a single rule.
Uri webSocketUriFor(String httpBase) {
  final uri = Uri.parse(httpBase);
  final basePath = uri.path.endsWith('/') ? uri.path.substring(0, uri.path.length - 1) : uri.path;
  return uri.replace(scheme: uri.scheme == 'https' ? 'wss' : 'ws', path: '$basePath/api/ws');
}

/// The server URL is editable from the sign-in screen so both phones can point
/// at a laptop on the same Wi-Fi or at a deployed server without rebuilding.
/// Only an address the user saved in the app overrides the `.env` value.
class ServerUrlNotifier extends Notifier<String> {
  static const _prefsKey = 'server_url';

  @override
  String build() {
    final saved = ref.read(sharedPreferencesProvider).getString(_prefsKey);
    return saved ?? kDefaultServerUrl;
  }

  Future<void> set(String url) async {
    final normalized = normalizeServerUrl(url);
    final prefs = ref.read(sharedPreferencesProvider);
    if (normalized == kDefaultServerUrl) {
      await prefs.remove(_prefsKey); // keep following .env
    } else {
      await prefs.setString(_prefsKey, normalized);
    }
    state = normalized;
  }

  Future<void> reset() async {
    await ref.read(sharedPreferencesProvider).remove(_prefsKey);
    state = kDefaultServerUrl;
  }
}

final serverUrlProvider = NotifierProvider<ServerUrlNotifier, String>(ServerUrlNotifier.new);
