import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/storage/prefs.dart';
import '../../../core/storage/token_store.dart';
import '../data/auth_repository.dart';
import '../domain/app_user.dart';

sealed class AuthState {
  const AuthState();
}

class SignedOut extends AuthState {
  const SignedOut({this.reason});

  /// Shown on the sign-in screen, e.g. "Your session expired".
  final String? reason;
}

class SignedIn extends AuthState {
  const SignedIn(this.user);

  final AppUser user;
}

class AuthController extends AsyncNotifier<AuthState> {
  static const _cachedUserKey = 'cached_user';

  AuthRepository get _repo => ref.read(authRepositoryProvider);
  TokenStore get _tokens => ref.read(tokenStoreProvider);

  @override
  Future<AuthState> build() async {
    final token = await _tokens.load();
    if (token == null) return const SignedOut();

    try {
      final session = await _repo.refresh();
      await _persist(session);
      return SignedIn(session.user);
    } on ApiException catch (error) {
      if (error.isUnauthorized) {
        await _clear();
        return const SignedOut(reason: 'Your session expired. Please sign in again.');
      }
      // Offline or server down: keep the user signed in with the cached profile.
      final cached = _cachedUser();
      if (cached != null) return SignedIn(cached);
      rethrow;
    }
  }

  Future<void> login(String email, String password) async {
    final session = await _repo.login(email: email.trim(), password: password);
    await _persist(session);
    state = AsyncData(SignedIn(session.user));
  }

  Future<void> register({
    required String email,
    required String password,
    required String displayName,
    String? avatarEmoji,
  }) async {
    final session = await _repo.register(
      email: email.trim(),
      password: password,
      displayName: displayName.trim(),
      avatarEmoji: avatarEmoji,
    );
    await _persist(session);
    state = AsyncData(SignedIn(session.user));
  }

  /// Keeps the cached profile in sync after edits / pairing changes.
  Future<void> updateUser(AppUser user) async {
    await ref.read(sharedPreferencesProvider).setString(_cachedUserKey, jsonEncode(user.toJson()));
    state = AsyncData(SignedIn(user));
  }

  Future<void> signOut({String? reason}) async {
    await _clear();
    state = AsyncData(SignedOut(reason: reason));
  }

  Future<void> signOutEverywhere() async {
    try {
      await _repo.logoutEverywhere();
    } finally {
      await signOut();
    }
  }

  /// Called by the HTTP layer / socket when the server rejects our token.
  void handleUnauthorized() {
    if (state.value is SignedIn) {
      signOut(reason: 'Your session expired. Please sign in again.');
    }
  }

  Future<void> _persist(AuthSession session) async {
    await _tokens.save(session.token);
    await ref.read(sharedPreferencesProvider).setString(_cachedUserKey, jsonEncode(session.user.toJson()));
  }

  Future<void> _clear() async {
    await _tokens.clear();
    await ref.read(sharedPreferencesProvider).remove(_cachedUserKey);
  }

  AppUser? _cachedUser() {
    final raw = ref.read(sharedPreferencesProvider).getString(_cachedUserKey);
    if (raw == null) return null;
    try {
      return AppUser.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }
}

final authControllerProvider = AsyncNotifierProvider<AuthController, AuthState>(AuthController.new);

/// The signed-in user's id, or null. Watching this (instead of the whole auth
/// state) avoids rebuilding the socket when only the profile changes.
final currentUserIdProvider = Provider<String?>((ref) {
  final auth = ref.watch(authControllerProvider).value;
  return auth is SignedIn ? auth.user.id : null;
});

final currentUserProvider = Provider<AppUser?>((ref) {
  final auth = ref.watch(authControllerProvider).value;
  return auth is SignedIn ? auth.user : null;
});
