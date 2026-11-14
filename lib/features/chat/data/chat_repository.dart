import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../domain/chat_message.dart';

class ChatPage {
  const ChatPage(this.messages, this.hasMore);

  /// Newest first, as returned by the server.
  final List<ChatMessage> messages;
  final bool hasMore;
}

class ChatRepository {
  ChatRepository(this._dio);

  final Dio _dio;

  Future<ChatPage> history({String? beforeId, int limit = 40}) => guardApi(() async {
        final res = await _dio.get<Map<String, dynamic>>(
          '/messages',
          queryParameters: {'limit': limit, 'before': ?beforeId},
        );
        final data = res.data!;
        return ChatPage(
          [for (final m in data['messages'] as List) ChatMessage.fromJson(m as Map<String, dynamic>)],
          data['hasMore'] == true,
        );
      });
}

final chatRepositoryProvider = Provider<ChatRepository>((ref) => ChatRepository(ref.watch(dioProvider)));
