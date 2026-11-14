/// The quoted message shown inside a reply bubble (WhatsApp style).
class ReplyPreview {
  const ReplyPreview({required this.id, this.senderId, this.body, this.kind = 'text', this.deleted = false});

  final String id;
  final String? senderId;
  final String? body;
  final String kind;
  final bool deleted;

  factory ReplyPreview.fromJson(Map<String, dynamic> json) => ReplyPreview(
        id: json['id'] as String,
        senderId: json['senderId'] as String?,
        body: json['body'] as String?,
        kind: (json['kind'] as String?) ?? 'text',
        deleted: json['deleted'] == true,
      );

  factory ReplyPreview.of(ChatMessage message) => ReplyPreview(
        id: message.id,
        senderId: message.senderId,
        body: message.body.length > 240 ? message.body.substring(0, 240) : message.body,
        kind: message.kind,
      );
}

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
    this.replyTo,
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

  /// The message this one replies to.
  final ReplyPreview? replyTo;
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
        replyTo: json['replyTo'] is Map<String, dynamic>
            ? ReplyPreview.fromJson(json['replyTo'] as Map<String, dynamic>)
            : null,
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '')?.toLocal() ?? DateTime.now(),
      );

  factory ChatMessage.pending({
    required String clientId,
    required String senderId,
    required String body,
    String? mediaTitle,
    int? mediaPositionMs,
    ReplyPreview? replyTo,
  }) =>
      ChatMessage(
        id: 'local:$clientId',
        senderId: senderId,
        kind: 'text',
        body: body,
        clientId: clientId,
        mediaTitle: mediaTitle,
        mediaPositionMs: mediaPositionMs,
        replyTo: replyTo,
        createdAt: DateTime.now(),
        pending: true,
      );
}
