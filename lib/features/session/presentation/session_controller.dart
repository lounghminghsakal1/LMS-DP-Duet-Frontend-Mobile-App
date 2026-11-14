import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/server_config.dart';
import '../../../core/storage/token_store.dart';
import '../../auth/presentation/auth_controller.dart';
import '../data/session_client.dart';
import '../data/session_socket.dart';
import '../domain/room_state.dart';

class SessionSnapshot {
  const SessionSnapshot({
    this.connection = ConnectionStatus.disconnected,
    this.room,
    this.roomLoaded = false,
    this.myUserId,
    this.partnerTyping = false,
  });

  final ConnectionStatus connection;
  final RoomState? room;

  /// True once the server told us about the room at least once.
  final bool roomLoaded;
  final String? myUserId;
  final bool partnerTyping;

  bool get isConnected => connection == ConnectionStatus.connected;
  RoomMember? get me => room?.member(myUserId);
  RoomMember? get partner => room?.partnerOf(myUserId);
  RoomMedia? get media => room?.media;
}

/// App-wide stream of one-off realtime events (chat, reactions, nudges, toasts).
/// Lives outside the controller so listeners survive reconnects / user switches.
final sessionEventsProvider = Provider<StreamController<SessionEvent>>((ref) {
  final controller = StreamController<SessionEvent>.broadcast();
  ref.onDispose(controller.close);
  return controller;
});

/// Owns the realtime connection for the signed-in user.
class SessionController extends Notifier<SessionSnapshot> {
  SessionClient? _client;
  StreamSubscription<void>? _changesSub;
  StreamSubscription<SessionEvent>? _eventsSub;
  AppLifecycleListener? _lifecycle;

  /// The live client (null while signed out).
  SessionClient? get client => _client;

  int serverNow() => _client?.serverNow() ?? DateTime.now().millisecondsSinceEpoch;

  @override
  SessionSnapshot build() {
    final userId = ref.watch(currentUserIdProvider);
    final serverUrl = ref.watch(serverUrlProvider);
    ref.onDispose(_teardown);

    final token = ref.read(tokenStoreProvider).token;
    if (userId == null || token == null) return const SessionSnapshot();

    final client = SessionClient(
      uri: webSocketUriFor(serverUrl),
      token: token,
      onAuthRejected: () => ref.read(authControllerProvider.notifier).handleUnauthorized(),
    );
    _client = client;
    final bus = ref.read(sessionEventsProvider);
    _changesSub = client.changes.listen((_) => _mirror(client));
    _eventsSub = client.events.listen((event) {
      if (!bus.isClosed) bus.add(event);
    });
    _lifecycle = AppLifecycleListener(onResume: client.reconnectNow);
    client.connect();
    return SessionSnapshot(connection: ConnectionStatus.connecting, myUserId: userId);
  }

  void _mirror(SessionClient client) {
    if (!ref.mounted || !identical(client, _client)) return;
    state = SessionSnapshot(
      connection: client.connection,
      room: client.room,
      roomLoaded: client.roomLoaded,
      myUserId: client.myUserId ?? state.myUserId,
      partnerTyping: client.partnerTyping,
    );
  }

  void _teardown() {
    _changesSub?.cancel();
    _eventsSub?.cancel();
    _lifecycle?.dispose();
    _client?.dispose();
    _client = null;
  }
}

final sessionControllerProvider = NotifierProvider<SessionController, SessionSnapshot>(SessionController.new);
