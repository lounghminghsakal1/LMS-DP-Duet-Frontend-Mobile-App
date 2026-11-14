import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../domain/app_user.dart';

class AuthRepository {
  AuthRepository(this._dio);

  final Dio _dio;

  Future<AuthSession> login({required String email, required String password}) => guardApi(() async {
        final res = await _dio.post<Map<String, dynamic>>(
          '/auth/login',
          data: {'email': email, 'password': password},
        );
        return AuthSession.fromJson(res.data!);
      });

  Future<AuthSession> register({
    required String email,
    required String password,
    required String displayName,
    String? avatarEmoji,
  }) =>
      guardApi(() async {
        final res = await _dio.post<Map<String, dynamic>>(
          '/auth/register',
          data: {
            'email': email,
            'password': password,
            'displayName': displayName,
            'avatarEmoji': ?avatarEmoji,
          },
        );
        return AuthSession.fromJson(res.data!);
      });

  Future<AuthSession> refresh() => guardApi(() async {
        final res = await _dio.post<Map<String, dynamic>>('/auth/refresh');
        return AuthSession.fromJson(res.data!);
      });

  Future<void> logoutEverywhere() => guardApi(() async {
        await _dio.post<void>('/auth/logout-all');
      });

  Future<AppUser> updateProfile({String? displayName, String? avatarEmoji}) => guardApi(() async {
        final res = await _dio.patch<Map<String, dynamic>>(
          '/me',
          data: {'displayName': ?displayName, 'avatarEmoji': ?avatarEmoji},
        );
        return AppUser.fromJson(res.data!['user'] as Map<String, dynamic>);
      });

  /// Pings /health on an arbitrary server URL (used by the server settings sheet).
  static Future<bool> checkServer(String baseUrl) async {
    final dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 5), receiveTimeout: const Duration(seconds: 5)));
    try {
      final res = await dio.get<Map<String, dynamic>>('$baseUrl/health');
      return res.data?['ok'] == true;
    } catch (_) {
      return false;
    } finally {
      dio.close();
    }
  }
}

final authRepositoryProvider = Provider<AuthRepository>((ref) => AuthRepository(ref.watch(dioProvider)));
