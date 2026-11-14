class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.senderId,
    required this.kind,
    required this.body,
    required this.createdAt,
    this.clientId,
    this.mediaTitle,
    this.mediaPositionMs,
    this.pending = false,
  });

  /// Server id, or `local:{clientId}` while the message is still being sent.
  final String id;
  final String? senderId;

  /// "text" or "system" (e.g. "🎬 Sam started 'Inception'").
  final String kind;
  final String body;
  final DateTime createdAt;
  final String? clientId;

  /// What was playing (and where) when this was sent — tap to jump there.
  final String? mediaTitle;
  final int? mediaPositionMs;
  final bool pending;

  bool get isSystem => kind == 'system';

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
        id: json['id'] as String,
        senderId: json['senderId'] as String?,
        kind: (json['kind'] as String?) ?? 'text',
        body: json['body'] as String,
        clientId: json['clientId'] as String?,
        mediaTitle: json['mediaTitle'] as String?,
        mediaPositionMs: (json['mediaPositionMs'] as num?)?.toInt(),
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '')?.toLocal() ?? DateTime.now(),
      );

  factory ChatMessage.pending({
    required String clientId,
    required String senderId,
    required String body,
    String? mediaTitle,
    int? mediaPositionMs,
  }) =>
      ChatMessage(
        id: 'local:$clientId',
        senderId: senderId,
        kind: 'text',
        body: body,
        clientId: clientId,
        mediaTitle: mediaTitle,
        mediaPositionMs: mediaPositionMs,
        createdAt: DateTime.now(),
        pending: true,
      );
}
