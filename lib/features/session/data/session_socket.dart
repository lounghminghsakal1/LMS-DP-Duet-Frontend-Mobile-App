import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

enum ConnectionStatus { disconnected, connecting, connected }

class SocketFrame {
  const SocketFrame(this.type, this.data);

  final String type;
  final Map<String, dynamic> data;
}

/// Close codes the server uses when the token is no longer valid.
const kAuthCloseCodes = {4401, 4001};

/// A self-healing WebSocket: authenticates with the JWT as the first frame,
/// reconnects with exponential backoff, and exposes decoded frames as a stream.
class SessionSocket {
  SessionSocket({
    required this.uri,
    required this.token,
    this.onAuthRejected,
    WebSocketChannel Function(Uri uri)? connector,
  }) : _connector = connector ??
            ((uri) => IOWebSocketChannel.connect(
                  uri,
                  pingInterval: const Duration(seconds: 20),
                  connectTimeout: const Duration(seconds: 10),
                ));

  final Uri uri;
  final String token;
  final void Function(int closeCode)? onAuthRejected;
  final WebSocketChannel Function(Uri uri) _connector;

  final _frames = StreamController<SocketFrame>.broadcast();
  final _statuses = StreamController<ConnectionStatus>.broadcast();

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  Timer? _reconnectTimer;
  ConnectionStatus _status = ConnectionStatus.disconnected;
  bool _wanted = false;
  bool _disposed = false;
  int _attempt = 0;

  Stream<SocketFrame> get frames => _frames.stream;
  Stream<ConnectionStatus> get statuses => _statuses.stream;
  ConnectionStatus get status => _status;
  bool get isConnected => _status == ConnectionStatus.connected;

  void connect() {
    if (_disposed) return;
    _wanted = true;
    _open();
  }

  /// Skip the backoff wait (e.g. the app came back to the foreground).
  void reconnectNow() {
    if (_disposed || !_wanted || _status != ConnectionStatus.disconnected) return;
    _reconnectTimer?.cancel();
    _attempt = 0;
    _open();
  }

  /// Sends a frame if connected. Returns false when it could not be sent.
  bool send(String type, [Map<String, dynamic> data = const {}]) {
    if (_status != ConnectionStatus.connected) return false;
    return _sendRaw(type, data);
  }

  Future<void> dispose() async {
    _disposed = true;
    _wanted = false;
    _reconnectTimer?.cancel();
    await _subscription?.cancel();
    try {
      await _channel?.sink.close(1000);
    } catch (_) {}
    _channel = null;
    await _frames.close();
    await _statuses.close();
  }

  // ------------------------------------------------------------------ internals

  Future<void> _open() async {
    if (_disposed || _status != ConnectionStatus.disconnected) return;
    _setStatus(ConnectionStatus.connecting);
    final WebSocketChannel channel;
    try {
      channel = _connector(uri);
      _channel = channel;
      await channel.ready;
    } catch (_) {
      _channel = null;
      _setStatus(ConnectionStatus.disconnected);
      _scheduleReconnect();
      return;
    }
    if (_disposed) {
      await channel.sink.close(1000);
      return;
    }
    _subscription = channel.stream.listen(
      _onData,
      onDone: () => _onDone(channel),
      onError: (_) {},
      cancelOnError: false,
    );
    _sendRaw('auth', {'token': token});
  }

  void _onData(dynamic raw) {
    if (raw is! String) return;
    final Map<String, dynamic> decoded;
    try {
      decoded = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    final type = decoded['type'] as String?;
    if (type == null) return;
    final data = decoded['data'];
    final frame = SocketFrame(type, data is Map<String, dynamic> ? data : const {});
    if (type == 'auth:ok') {
      _attempt = 0;
      _setStatus(ConnectionStatus.connected);
    }
    if (!_frames.isClosed) _frames.add(frame);
  }

  void _onDone(WebSocketChannel channel) {
    if (!identical(channel, _channel)) return;
    final code = channel.closeCode;
    _subscription?.cancel();
    _subscription = null;
    _channel = null;
    _setStatus(ConnectionStatus.disconnected);
    if (code != null && kAuthCloseCodes.contains(code)) {
      _wanted = false;
      onAuthRejected?.call(code);
      return;
    }
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_disposed || !_wanted) return;
    _reconnectTimer?.cancel();
    final base = math.min(15000, 600 * math.pow(2, _attempt).toInt());
    final jitter = math.Random().nextInt(400);
    _attempt = math.min(_attempt + 1, 10);
    _reconnectTimer = Timer(Duration(milliseconds: base + jitter), _open);
  }

  bool _sendRaw(String type, Map<String, dynamic> data) {
    final channel = _channel;
    if (channel == null) return false;
    try {
      channel.sink.add(jsonEncode({'type': type, 'data': data}));
      return true;
    } catch (_) {
      return false;
    }
  }

  void _setStatus(ConnectionStatus status) {
    if (_status == status) return;
    _status = status;
    if (!_statuses.isClosed) _statuses.add(status);
  }
}
