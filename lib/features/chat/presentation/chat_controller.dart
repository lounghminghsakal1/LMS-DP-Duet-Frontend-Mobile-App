import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/ids.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../pairing/presentation/overview_controller.dart';
import '../../session/data/session_client.dart';
import '../../session/presentation/session_controller.dart';
import '../data/chat_repository.dart';
import '../domain/chat_message.dart';

class ChatState {
  const ChatState({
    this.messages = const [],
    this.loading = true,
    this.loadingMore = false,
    this.hasMore = false,
    this.unread = 0,
    this.error,
  });

  /// Oldest first.
  final List<ChatMessage> messages;
  final bool loading;
  final bool loadingMore;
  final bool hasMore;
  final int unread;
  final String? error;

  ChatState copyWith({
    List<ChatMessage>? messages,
    bool? loading,
    bool? loadingMore,
    bool? hasMore,
    int? unread,
    String? error,
    bool clearError = false,
  }) =>
      ChatState(
        messages: messages ?? this.messages,
        loading: loading ?? this.loading,
        loadingMore: loadingMore ?? this.loadingMore,
        hasMore: hasMore ?? this.hasMore,
        unread: unread ?? this.unread,
        error: clearError ? null : (error ?? this.error),
      );
}

class ChatController extends Notifier<ChatState> {
  int _visibleViews = 0;

  ChatRepository get _repo => ref.read(chatRepositoryProvider);
  String? get _myId => ref.read(currentUserIdProvider);

  @override
  ChatState build() {
    final userId = ref.watch(currentUserIdProvider);
    if (userId == null) return const ChatState(loading: false);
    // Reload when the partner changes (paired / unpaired).
    ref.watch(overviewControllerProvider.select((o) => o.value?.partner?.id));

    final sub = ref.read(sessionEventsProvider).stream.listen(_onEvent);
    ref.onDispose(sub.cancel);
    Future.microtask(_loadLatest);
    return const ChatState();
  }

  Future<void> _loadLatest() async {
    try {
      final page = await _repo.history();
      if (!ref.mounted) return;
      final pending = state.messages.where((m) => m.pending).toList();
      state = state.copyWith(
        messages: [...page.messages.reversed, ...pending],
        hasMore: page.hasMore,
        loading: false,
        clearError: true,
      );
    } catch (error) {
      if (!ref.mounted) return;
      state = state.copyWith(loading: false, error: error.toString());
    }
  }

  Future<void> loadMore() async {
    if (state.loadingMore || !state.hasMore) return;
    final oldest = state.messages.where((m) => !m.pending).firstOrNull;
    if (oldest == null) return;
    state = state.copyWith(loadingMore: true);
    try {
      final page = await _repo.history(beforeId: oldest.id);
      if (!ref.mounted) return;
      state = state.copyWith(
        messages: [...page.messages.reversed, ...state.messages],
        hasMore: page.hasMore,
        loadingMore: false,
      );
    } catch (_) {
      if (ref.mounted) state = state.copyWith(loadingMore: false);
    }
  }

  /// Sends a message. While playing, [positionMs] tags it with the current
  /// moment so either of you can tap it later to jump back to that scene.
  void send(String text, {int? positionMs, String? mediaTitle, ChatMessage? replyTo}) {
    final body = text.trim();
    final myId = _myId;
    if (body.isEmpty || myId == null) return;
    final clientId = randomId();
    // You can only quote messages the server already has.
    final quote = replyTo != null && !replyTo.pending ? ReplyPreview.of(replyTo) : null;
    final pending = ChatMessage.pending(
      clientId: clientId,
      senderId: myId,
      body: body,
      mediaTitle: positionMs != null ? mediaTitle : null,
      mediaPositionMs: positionMs,
      replyTo: quote,
    );
    state = state.copyWith(messages: [...state.messages, pending]);
    ref.read(sessionControllerProvider.notifier).client?.sendChat(
          text: body,
          clientId: clientId,
          positionMs: positionMs,
          replyToId: quote?.id,
        );
    // If we are offline it stays "pending" and is re-sent on reconnect.
  }

  void setTyping(bool typing) => ref.read(sessionControllerProvider.notifier).client?.typing(typing);

  /// Chat screens call this so unread counts only grow when nobody is looking.
  void viewVisible(bool visible) {
    _visibleViews = (_visibleViews + (visible ? 1 : -1)).clamp(0, 99);
    if (_visibleViews > 0 && state.unread != 0) state = state.copyWith(unread: 0);
  }

  void _onEvent(SessionEvent event) {
    switch (event) {
      case ChatMessageReceived(:final message):
        _addIncoming(message);
      case Reconnected():
        _resendPending();
        _loadLatest();
      case PairingChanged():
        _loadLatest();
      default:
        break;
    }
  }

  void _addIncoming(ChatMessage message) {
    final messages = [...state.messages];
    final byClient = message.clientId == null
        ? -1
        : messages.indexWhere((m) => m.clientId == message.clientId && m.senderId == message.senderId);
    if (byClient != -1) {
      messages[byClient] = message;
    } else if (messages.any((m) => m.id == message.id)) {
      return;
    } else {
      messages.add(message);
    }
    final fromPartner = message.senderId != _myId && !message.isSystem;
    state = state.copyWith(
      messages: messages,
      unread: fromPartner && _visibleViews == 0 ? state.unread + 1 : state.unread,
    );
  }

  void _resendPending() {
    final client = ref.read(sessionControllerProvider.notifier).client;
    if (client == null) return;
    for (final m in state.messages.where((m) => m.pending)) {
      client.sendChat(
        text: m.body,
        clientId: m.clientId!,
        positionMs: m.mediaPositionMs,
        replyToId: m.replyTo?.id,
      );
    }
  }
}

final chatControllerProvider = NotifierProvider<ChatController, ChatState>(ChatController.new);
