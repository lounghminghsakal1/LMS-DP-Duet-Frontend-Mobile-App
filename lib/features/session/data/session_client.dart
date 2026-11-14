import 'dart:async';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../../chat/domain/chat_message.dart';
import '../domain/clock_sync.dart';
import '../domain/room_state.dart';
import 'session_socket.dart';

sealed class SessionEvent {
  const SessionEvent();
}

/// The room changed for a reason worth telling the user about (play, pause, partner joined…).
class RoomEventReceived extends SessionEvent {
  const RoomEventReceived(this.event, this.room);

  final RoomEvent event;
  final RoomState? room;
}

class ChatMessageReceived extends SessionEvent {
  const ChatMessageReceived(this.message);

  final ChatMessage message;
}

class ReactionReceived extends SessionEvent {
  const ReactionReceived(this.userId, this.emoji);

  final String userId;
  final String emoji;
}

class NudgeReceived extends SessionEvent {
  const NudgeReceived(this.userId, this.kind);

  final String userId;
  final String kind;
}

/// pair:invite / pair:declined / pair:cancelled / pair:updated
class PairingChanged extends SessionEvent {
  const PairingChanged(this.type, this.data);

  final String type;
  final Map<String, dynamic> data;
}

class ServerErrorReceived extends SessionEvent {
  const ServerErrorReceived(this.code, this.message, this.requestType);

  final String code;
  final String message;
  final String? requestType;
}

class Reconnected extends SessionEvent {
  const Reconnected();
}

/// Plain-Dart realtime client (no Flutter), so it can be tested against a real
/// server. Owns the socket, the clock offset and the latest room state.
class SessionClient {
  SessionClient({
    required Uri uri,
    required String token,
    void Function()? onAuthRejected,
    WebSocketChannel Function(Uri uri)? connector,
    ClockSync? clock,
  }) : clock = clock ?? ClockSync() {
    _socket = SessionSocket(
      uri: uri,
      token: token,
      connector: connector,
      onAuthRejected: (_) => onAuthRejected?.call(),
    );
    _frameSub = _socket.frames.listen(_onFrame);
    _statusSub = _socket.statuses.listen(_onStatus);
  }

  final ClockSync clock;
  late final SessionSocket _socket;
  late final StreamSubscription<SocketFrame> _frameSub;
  late final StreamSubscription<ConnectionStatus> _statusSub;

  final _events = StreamController<SessionEvent>.broadcast();
  final _changes = StreamController<void>.broadcast();
  final _pongWaiters = <int, Completer<void>>{};

  Timer? _pingTimer;
  Timer? _typingTimer;
  bool _everConnected = false;
  bool _disposed = false;

  ConnectionStatus connection = ConnectionStatus.disconnected;
  RoomState? room;
  bool roomLoaded = false;
  String? myUserId;
  bool partnerTyping = false;

  Stream<SessionEvent> get events => _events.stream;

  /// Fires whenever [connection], [room] or [partnerTyping] changed.
  Stream<void> get changes => _changes.stream;
  bool get isConnected => connection == ConnectionStatus.connected;
  int serverNow() => clock.serverNow();

  RoomMember? get me => room?.member(myUserId);
  RoomMember? get partner => room?.partnerOf(myUserId);

  void connect() => _socket.connect();
  void reconnectNow() => _socket.reconnectNow();

  Future<void> dispose() async {
    _disposed = true;
    _pingTimer?.cancel();
    _typingTimer?.cancel();
    await _frameSub.cancel();
    await _statusSub.cancel();
    await _socket.dispose();
    await _events.close();
    await _changes.close();
  }

  // ------------------------------------------------------------------ commands

  bool loadMedia({
    required MediaKind kind,
    required String title,
    String? fingerprint,
    int? sizeBytes,
    int? durationMs,
    String? youtubeId,
    int startPositionMs = 0,
  }) {
    return _socket.send('media:load', {
      'kind': kind.name,
      'title': title,
      'fingerprint': ?fingerprint,
      'sizeBytes': ?sizeBytes,
      if (durationMs != null && durationMs > 0) 'durationMs': durationMs,
      'youtubeId': ?youtubeId,
      'startPositionMs': startPositionMs,
    });
  }

  bool markReady({String? fingerprint, bool force = false, int? durationMs}) => _socket.send('media:ready', {
        'fingerprint': ?fingerprint,
        if (force) 'force': true,
        if (durationMs != null && durationMs > 0) 'durationMs': durationMs,
      });

  bool markUnready() => _socket.send('media:unready');
  bool clearMedia() => _socket.send('media:clear');
  bool play(int positionMs) => _socket.send('playback:play', {'positionMs': positionMs});
  bool pause(int positionMs) => _socket.send('playback:pause', {'positionMs': positionMs});
  bool seek(int positionMs) => _socket.send('playback:seek', {'positionMs': positionMs});
  bool setRate(double rate) => _socket.send('playback:rate', {'rate': rate});
  bool setBuffering(bool buffering) => _socket.send('playback:buffering', {'buffering': buffering});
  bool typing(bool typing) => _socket.send('chat:typing', {'typing': typing});
  bool react(String emoji) => _socket.send('reaction', {'emoji': emoji});
  bool nudge(String kind) => _socket.send('nudge', {'kind': kind});

  bool sendChat({required String text, required String clientId, int? positionMs}) => _socket.send('chat:send', {
        'text': text,
        'clientId': clientId,
        'positionMs': ?positionMs,
      });

  /// Sends a few pings and waits for the answers, so the clock offset is good
  /// before anything time-critical happens.
  Future<void> syncClock({int samples = 5}) async {
    for (var i = 0; i < samples; i++) {
      final t0 = clock.localNow();
      final completer = Completer<void>();
      _pongWaiters[t0] = completer;
      if (!_socket.send('time:ping', {'t0': t0})) {
        _pongWaiters.remove(t0);
        return;
      }
      await completer.future.timeout(const Duration(seconds: 2), onTimeout: () {});
      _pongWaiters.remove(t0);
      await Future<void>.delayed(const Duration(milliseconds: 120));
    }
  }

  // ------------------------------------------------------------------ incoming

  void _onStatus(ConnectionStatus status) {
    connection = status;
    if (status == ConnectionStatus.connected) {
      final wasReconnect = _everConnected;
      _everConnected = true;
      syncClock();
      _pingTimer?.cancel();
      _pingTimer = Timer.periodic(const Duration(seconds: 15), (_) {
        _socket.send('time:ping', {'t0': clock.localNow()});
      });
      if (wasReconnect) _emit(const Reconnected());
    } else {
      _pingTimer?.cancel();
      partnerTyping = false;
    }
    _notify();
  }

  void _onFrame(SocketFrame frame) {
    final data = frame.data;
    switch (frame.type) {
      case 'auth:ok':
        myUserId = (data['user'] as Map?)?['id'] as String?;
        final serverTime = (data['serverTime'] as num?)?.toInt();
        // Rough first guess until the first pong arrives.
        if (serverTime != null) clock.setProvisional(serverTime);
      case 'time:pong':
        final t0 = (data['t0'] as num).toInt();
        clock.addSample(t0: t0, serverTime: (data['serverTime'] as num).toInt(), t1: clock.localNow());
        _pongWaiters[t0]?.complete();
      case 'room:state':
        final stateJson = data['state'];
        room = stateJson is Map<String, dynamic> ? RoomState.fromJson(stateJson) : null;
        roomLoaded = true;
        _notify();
        final eventJson = data['event'];
        if (eventJson is Map<String, dynamic>) {
          _emit(RoomEventReceived(RoomEvent.fromJson(eventJson), room));
        }
      case 'chat:message':
        _emit(ChatMessageReceived(ChatMessage.fromJson(data)));
        if (data['senderId'] != myUserId && partnerTyping) {
          partnerTyping = false;
          _notify();
        }
      case 'chat:typing':
        partnerTyping = data['typing'] == true;
        _typingTimer?.cancel();
        if (partnerTyping) {
          _typingTimer = Timer(const Duration(seconds: 6), () {
            partnerTyping = false;
            _notify();
          });
        }
        _notify();
      case 'reaction':
        _emit(ReactionReceived(data['userId'] as String, data['emoji'] as String));
      case 'nudge':
        _emit(NudgeReceived(data['userId'] as String, data['kind'] as String));
      case 'pair:invite' || 'pair:declined' || 'pair:cancelled' || 'pair:updated':
        _emit(PairingChanged(frame.type, data));
      case 'error':
        _emit(ServerErrorReceived(
          (data['code'] as String?) ?? 'error',
          (data['message'] as String?) ?? 'Something went wrong.',
          data['requestType'] as String?,
        ));
    }
  }

  void _emit(SessionEvent event) {
    if (!_disposed && !_events.isClosed) _events.add(event);
  }

  void _notify() {
    if (!_disposed && !_changes.isClosed) _changes.add(null);
  }
}
