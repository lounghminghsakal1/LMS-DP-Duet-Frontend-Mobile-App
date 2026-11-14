import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Keeps the JWT in the platform keystore and caches it in memory for fast access.
class TokenStore {
  TokenStore(this._secure);

  static const _key = 'duet_auth_token';
  final FlutterSecureStorage _secure;
  String? _token;

  String? get token => _token;

  Future<String?> load() async {
    try {
      _token = await _secure.read(key: _key);
    } catch (_) {
      // Keystore can fail after an OS restore; treat as signed out.
      _token = null;
    }
    return _token;
  }

  Future<void> save(String token) async {
    _token = token;
    await _secure.write(key: _key, value: token);
  }

  Future<void> clear() async {
    _token = null;
    try {
      await _secure.delete(key: _key);
    } catch (_) {}
  }
}

final tokenStoreProvider = Provider<TokenStore>((ref) => TokenStore(const FlutterSecureStorage()));
