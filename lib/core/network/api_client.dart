import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/server_config.dart';
import '../storage/token_store.dart';

/// An error that is safe to show to the user.
class ApiException implements Exception {
  const ApiException(this.message, {this.code = 'unknown', this.status, this.details});

  final String message;
  final String code;
  final int? status;
  final Map<String, dynamic>? details;

  bool get isUnauthorized => status == 401;
  bool get isNetwork => code == 'network';

  @override
  String toString() => message;
}

ApiException toApiException(Object error) {
  if (error is ApiException) return error;
  if (error is DioException) {
    final response = error.response;
    final body = response?.data;
    if (body is Map && body['error'] is Map) {
      final err = body['error'] as Map;
      return ApiException(
        (err['message'] as String?) ?? 'Something went wrong.',
        code: (err['code'] as String?) ?? 'unknown',
        status: response?.statusCode,
        details: (err['details'] as Map?)?.cast<String, dynamic>(),
      );
    }
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.connectionError:
        return const ApiException(
          "Can't reach the Duet server. Check your internet and the server address.",
          code: 'network',
        );
      default:
        return ApiException(
          'Unexpected server response (${response?.statusCode ?? 'no status'}).',
          status: response?.statusCode,
        );
    }
  }
  return ApiException(error.toString());
}

/// Runs a request and converts any failure into an [ApiException].
Future<T> guardApi<T>(Future<T> Function() request) async {
  try {
    return await request();
  } catch (error) {
    throw toApiException(error);
  }
}

/// Called when any authenticated request gets a 401 (token revoked/expired).
typedef UnauthorizedCallback = void Function();

final unauthorizedCallbackProvider = Provider<UnauthorizedCallback?>((ref) => null);

final dioProvider = Provider<Dio>((ref) {
  final baseUrl = ref.watch(serverUrlProvider);
  final dio = Dio(
    BaseOptions(
      baseUrl: '$baseUrl/api',
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 15),
      sendTimeout: const Duration(seconds: 15),
      contentType: Headers.jsonContentType,
      responseType: ResponseType.json,
    ),
  );

  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        final token = ref.read(tokenStoreProvider).token;
        if (token != null && options.headers['Authorization'] == null) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        handler.next(options);
      },
      onError: (error, handler) {
        final path = error.requestOptions.path;
        final isAuthAttempt = path.contains('/auth/login') || path.contains('/auth/register');
        if (error.response?.statusCode == 401 && !isAuthAttempt) {
          ref.read(unauthorizedCallbackProvider)?.call();
        }
        handler.next(error);
      },
    ),
  );

  ref.onDispose(dio.close);
  return dio;
});
