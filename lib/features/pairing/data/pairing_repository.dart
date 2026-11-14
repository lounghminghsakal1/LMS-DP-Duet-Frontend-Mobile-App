import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../domain/overview.dart';

class PairingRepository {
  PairingRepository(this._dio);

  final Dio _dio;

  Future<Overview> overview() => guardApi(() async {
        final res = await _dio.get<Map<String, dynamic>>('/me');
        return Overview.fromJson(res.data!);
      });

  /// Returns true when this immediately paired us (they had already invited us).
  Future<bool> invite(String email) => guardApi(() async {
        final res = await _dio.post<Map<String, dynamic>>('/pair/invites', data: {'email': email.trim()});
        return res.data?['paired'] == true;
      });

  Future<void> accept(String inviteId) => guardApi(() async {
        await _dio.post<void>('/pair/invites/$inviteId/accept');
      });

  Future<void> decline(String inviteId) => guardApi(() async {
        await _dio.post<void>('/pair/invites/$inviteId/decline');
      });

  Future<void> cancel(String inviteId) => guardApi(() async {
        await _dio.delete<void>('/pair/invites/$inviteId');
      });

  Future<void> unpair() => guardApi(() async {
        await _dio.delete<void>('/pair');
      });
}

final pairingRepositoryProvider = Provider<PairingRepository>((ref) => PairingRepository(ref.watch(dioProvider)));
