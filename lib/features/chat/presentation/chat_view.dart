import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/format.dart';
import '../../../core/widgets/common.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../session/presentation/presence.dart';
import '../../session/presentation/session_controller.dart';
import '../domain/chat_message.dart';
import 'chat_controller.dart';

/// Message list + composer. Used full-screen and under/next to the player.
/// Swipe a message to the right (or long-press → Reply) to quote it, WhatsApp style.
class ChatView extends ConsumerStatefulWidget {
  const ChatView({
    super.key,
    this.currentPositionMs,
    this.currentMediaTitle,
    this.onTimestampTap,
    this.compact = false,
    this.transparent = false,
  });

  /// While watching: returns the playback position so messages get a timestamp.
  final int? Function()? currentPositionMs;
  final String? currentMediaTitle;

  /// Tapping a "🎬 1:02:13" chip. Only provided while that media is open.
  final void Function(ChatMessage message)? onTimestampTap;
  final bool compact;

  /// For the landscape overlay on top of the video.
  final bool transparent;

  @override
  ConsumerState<ChatView> createState() => _ChatViewState();
}

class _ChatViewState extends ConsumerState<ChatView> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _focus = FocusNode();
  final _itemKeys = <String, GlobalKey>{};
  Timer? _typingTimer;
  Timer? _highlightTimer;
  bool _typingSent = false;
  ChatMessage? _replyingTo;
  String? _highlightedId;
  late final ChatController _chat;

  @override
  void initState() {
    super.initState();
    _chat = ref.read(chatControllerProvider.notifier);
    WidgetsBinding.instance.addPostFrameCallback((_) => _chat.viewVisible(true));
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 200) _chat.loadMore();
    });
  }

  @override
  void dispose() {
    _chat.viewVisible(false);
    if (_typingSent) _chat.setTyping(false);
    _typingTimer?.cancel();
    _highlightTimer?.cancel();
    _input.dispose();
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    if (value.trim().isEmpty) {
      _stopTyping();
      return;
    }
    if (!_typingSent) {
      _typingSent = true;
      _chat.setTyping(true);
    }
    _typingTimer?.cancel();
    _typingTimer = Timer(const Duration(seconds: 3), _stopTyping);
  }

  void _stopTyping() {
    _typingTimer?.cancel();
    if (_typingSent) {
      _typingSent = false;
      _chat.setTyping(false);
    }
  }

  void _send() {
    final text = _input.text;
    if (text.trim().isEmpty) return;
    _chat.send(
      text,
      positionMs: widget.currentPositionMs?.call(),
      mediaTitle: widget.currentMediaTitle,
      replyTo: _replyingTo,
    );
    _input.clear();
    _stopTyping();
    setState(() => _replyingTo = null);
    if (_scroll.hasClients) {
      _scroll.animateTo(0, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    }
  }

  void _startReply(ChatMessage message) {
    if (message.pending || message.isSystem) return;
    HapticFeedback.selectionClick();
    setState(() => _replyingTo = message);
    _focus.requestFocus();
  }

  Future<void> _showActions(ChatMessage message) async {
    if (message.isSystem) return;
    HapticFeedback.mediumImpact();
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!message.pending)
              ListTile(
                leading: const Icon(Icons.reply_rounded),
                title: const Text('Reply'),
                onTap: () => Navigator.pop(context, 'reply'),
              ),
            ListTile(
              leading: const Icon(Icons.copy_rounded),
              title: const Text('Copy'),
              onTap: () => Navigator.pop(context, 'copy'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (action == 'reply') _startReply(message);
    if (action == 'copy') {
      await Clipboard.setData(ClipboardData(text: message.body));
      if (mounted) showToast(context, 'Copied');
    }
  }

  /// Tapping a quote scrolls to the original message and highlights it.
  Future<void> _jumpTo(String messageId, List<ChatMessage> newestFirst) async {
    final index = newestFirst.indexWhere((m) => m.id == messageId);
    if (index == -1) {
      showToast(context, 'That message is further back in your chat');
      _chat.loadMore();
      return;
    }
    var ctx = _itemKeys[messageId]?.currentContext;
    if (ctx == null && _scroll.hasClients) {
      // Not built yet (off-screen): scroll roughly there first.
      final estimate = (index * 74.0).clamp(0.0, _scroll.position.maxScrollExtent);
      await _scroll.animateTo(estimate, duration: const Duration(milliseconds: 350), curve: Curves.easeOut);
      await WidgetsBinding.instance.endOfFrame;
      ctx = _itemKeys[messageId]?.currentContext;
    }
    if (ctx != null && ctx.mounted) {
      await Scrollable.ensureVisible(ctx, alignment: 0.4, duration: const Duration(milliseconds: 300));
    }
    if (!mounted) return;
    setState(() => _highlightedId = messageId);
    _highlightTimer?.cancel();
    _highlightTimer = Timer(const Duration(milliseconds: 1400), () {
      if (mounted) setState(() => _highlightedId = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    final chat = ref.watch(chatControllerProvider);
    final myId = ref.watch(currentUserIdProvider);
    final session = ref.watch(sessionControllerProvider);
    final partner = session.partner;
    final partnerName = partner?.displayName ?? 'Partner';
    final messages = chat.messages.reversed.toList();
    String nameOf(String? senderId) => senderId == myId ? 'You' : partnerName;

    return Column(
      children: [
        Expanded(
          child: chat.loading && messages.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : messages.isEmpty
                  ? _EmptyChat(partnerName: partner?.displayName)
                  : ListView.builder(
                      controller: _scroll,
                      reverse: true,
                      padding: EdgeInsets.symmetric(horizontal: 12, vertical: widget.compact ? 6 : 12),
                      itemCount: messages.length + (chat.loadingMore ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (index >= messages.length) {
                          return const Padding(
                            padding: EdgeInsets.all(12),
                            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                          );
                        }
                        final message = messages[index];
                        final older = index + 1 < messages.length ? messages[index + 1] : null;
                        final groupedWithOlder = older != null &&
                            older.senderId == message.senderId &&
                            !older.isSystem &&
                            message.createdAt.difference(older.createdAt).inMinutes < 3;
                        return KeyedSubtree(
                          key: _itemKeys.putIfAbsent(message.id, GlobalKey.new),
                          child: _MessageTile(
                            message: message,
                            mine: message.senderId == myId,
                            showGap: !groupedWithOlder,
                            highlighted: message.id == _highlightedId,
                            transparent: widget.transparent,
                            quoteName: message.replyTo == null ? null : nameOf(message.replyTo!.senderId),
                            onTimestampTap: widget.onTimestampTap,
                            onReply: () => _startReply(message),
                            onLongPress: () => _showActions(message),
                            onQuoteTap: message.replyTo == null ? null : () => _jumpTo(message.replyTo!.id, messages),
                          ),
                        );
                      },
                    ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          child: session.partnerTyping
              ? Padding(
                  padding: const EdgeInsets.only(left: 18, bottom: 4),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '$partnerName is typing…',
                      style: const TextStyle(color: DuetColors.textMuted, fontSize: 12, fontStyle: FontStyle.italic),
                    ),
                  ),
                )
              : const SizedBox.shrink(),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          child: _replyingTo == null
              ? const SizedBox(width: double.infinity)
              : _ReplyBar(
                  name: _replyingTo!.senderId == myId ? 'yourself' : partnerName,
                  body: _replyingTo!.body,
                  onClose: () => setState(() => _replyingTo = null),
                ),
        ),
        _Composer(
          controller: _input,
          focusNode: _focus,
          onChanged: _onChanged,
          onSend: _send,
          compact: widget.compact,
          transparent: widget.transparent,
          hint: widget.currentPositionMs != null ? 'Say something about this moment…' : 'Message',
        ),
      ],
    );
  }
}

class _MessageTile extends StatelessWidget {
  const _MessageTile({
    required this.message,
    required this.mine,
    required this.showGap,
    required this.highlighted,
    required this.transparent,
    required this.onReply,
    required this.onLongPress,
    this.quoteName,
    this.onQuoteTap,
    this.onTimestampTap,
  });

  final ChatMessage message;
  final bool mine;
  final bool showGap;
  final bool highlighted;
  final bool transparent;
  final String? quoteName;
  final VoidCallback onReply;
  final VoidCallback onLongPress;
  final VoidCallback? onQuoteTap;
  final void Function(ChatMessage message)? onTimestampTap;

  @override
  Widget build(BuildContext context) {
    if (message.isSystem) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: DuetColors.surfaceHigh.withValues(alpha: transparent ? 0.7 : 1),
              borderRadius: BorderRadius.circular(99),
            ),
            child: Text(
              '${message.body} · ${formatClock(message.createdAt)}',
              style: const TextStyle(color: DuetColors.textMuted, fontSize: 12),
            ),
          ),
        ),
      );
    }

    final bubbleColor = mine ? null : DuetColors.surfaceHigh.withValues(alpha: transparent ? 0.82 : 1);
    final radius = BorderRadius.only(
      topLeft: const Radius.circular(18),
      topRight: const Radius.circular(18),
      bottomLeft: Radius.circular(mine ? 18 : 4),
      bottomRight: Radius.circular(mine ? 4 : 18),
    );

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      color: highlighted ? DuetColors.pink.withValues(alpha: 0.16) : Colors.transparent,
      padding: EdgeInsets.only(top: showGap ? 10 : 2),
      child: _SwipeToReply(
        enabled: !message.pending,
        onReply: onReply,
        child: GestureDetector(
          onLongPress: onLongPress,
          child: Row(
            mainAxisAlignment: mine ? MainAxisAlignment.end : MainAxisAlignment.start,
            children: [
              Flexible(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 300),
                  child: Opacity(
                    opacity: message.pending ? 0.6 : 1,
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(14, 9, 14, 8),
                      decoration: BoxDecoration(
                        color: bubbleColor,
                        gradient: mine ? DuetColors.accentGradient : null,
                        borderRadius: radius,
                      ),
                      child: Column(
                        crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (message.replyTo != null) ...[
                            _QuoteBlock(reply: message.replyTo!, name: quoteName ?? '', onTap: onQuoteTap),
                            const SizedBox(height: 6),
                          ],
                          if (message.mediaPositionMs != null) ...[
                            _TimestampChip(message: message, onTap: onTimestampTap),
                            const SizedBox(height: 5),
                          ],
                          Text(message.body, style: const TextStyle(color: Colors.white, fontSize: 15, height: 1.3)),
                          const SizedBox(height: 3),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                formatClock(message.createdAt),
                                style: TextStyle(color: Colors.white.withValues(alpha: 0.65), fontSize: 10.5),
                              ),
                              if (mine) ...[
                                const SizedBox(width: 4),
                                Icon(
                                  message.pending ? Icons.schedule_rounded : Icons.done_rounded,
                                  size: 12,
                                  color: Colors.white.withValues(alpha: 0.7),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Drag a bubble to the right to reply (like WhatsApp).
class _SwipeToReply extends StatefulWidget {
  const _SwipeToReply({required this.child, required this.onReply, required this.enabled});

  final Widget child;
  final VoidCallback onReply;
  final bool enabled;

  @override
  State<_SwipeToReply> createState() => _SwipeToReplyState();
}

class _SwipeToReplyState extends State<_SwipeToReply> with SingleTickerProviderStateMixin {
  static const _trigger = 56.0;
  static const _max = 80.0;
  late final AnimationController _back = AnimationController(vsync: this, duration: const Duration(milliseconds: 180))
    ..addListener(() => setState(() => _dx = _from * (1 - _back.value)));
  double _dx = 0;
  double _from = 0;
  bool _armed = false;

  @override
  void dispose() {
    _back.dispose();
    super.dispose();
  }

  void _update(DragUpdateDetails details) {
    setState(() => _dx = (_dx + details.delta.dx).clamp(0, _max));
    if (!_armed && _dx >= _trigger) {
      _armed = true;
      HapticFeedback.lightImpact();
    } else if (_armed && _dx < _trigger) {
      _armed = false;
    }
  }

  void _end([DragEndDetails? _]) {
    if (_armed) widget.onReply();
    _armed = false;
    _from = _dx;
    _back.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragUpdate: _update,
      onHorizontalDragEnd: _end,
      onHorizontalDragCancel: _end,
      child: Stack(
        alignment: Alignment.centerLeft,
        children: [
          Opacity(
            opacity: (_dx / _trigger).clamp(0, 1).toDouble(),
            child: Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Icon(Icons.reply_rounded, color: _armed ? DuetColors.pink : DuetColors.textMuted, size: 22),
            ),
          ),
          Transform.translate(offset: Offset(_dx, 0), child: widget.child),
        ],
      ),
    );
  }
}

/// The quoted message inside a reply bubble.
class _QuoteBlock extends StatelessWidget {
  const _QuoteBlock({required this.reply, required this.name, this.onTap});

  final ReplyPreview reply;
  final String name;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minWidth: 120),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.22),
          borderRadius: BorderRadius.circular(10),
        ),
        child: IntrinsicHeight(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: 4,
                decoration: const BoxDecoration(
                  color: DuetColors.peach,
                  borderRadius: BorderRadius.horizontal(left: Radius.circular(10)),
                ),
              ),
              Flexible(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 6, 10, 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(color: DuetColors.peach, fontWeight: FontWeight.w700, fontSize: 12),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        reply.deleted ? 'Message deleted' : (reply.body ?? ''),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Replying to Sam" bar above the text field.
class _ReplyBar extends StatelessWidget {
  const _ReplyBar({required this.name, required this.body, required this.onClose});

  final String name;
  final String body;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(10, 4, 10, 0),
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      decoration: BoxDecoration(
        color: DuetColors.surfaceHigh,
        borderRadius: BorderRadius.circular(14),
        border: const Border(left: BorderSide(color: DuetColors.pink, width: 4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.reply_rounded, size: 18, color: DuetColors.pink),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Replying to $name',
                  style: const TextStyle(color: DuetColors.pink, fontWeight: FontWeight.w700, fontSize: 12),
                ),
                Text(body, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: DuetColors.textMuted)),
              ],
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: onClose,
            icon: const Icon(Icons.close_rounded, size: 18),
          ),
        ],
      ),
    );
  }
}

class _TimestampChip extends StatelessWidget {
  const _TimestampChip({required this.message, this.onTap});

  final ChatMessage message;
  final void Function(ChatMessage message)? onTap;

  @override
  Widget build(BuildContext context) {
    final label = '${message.mediaTitle != null ? '🎬 ' : ''}${formatPosition(message.mediaPositionMs!)}';
    return GestureDetector(
      onTap: onTap == null ? null : () => onTap!(message),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.22),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w700),
            ),
            if (message.mediaTitle != null && onTap == null) ...[
              const SizedBox(width: 4),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 140),
                child: Text(
                  message.mediaTitle!,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 11),
                ),
              ),
            ],
            if (onTap != null) ...[
              const SizedBox(width: 3),
              const Icon(Icons.replay_rounded, size: 12, color: Colors.white),
            ],
          ],
        ),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onSend,
    required this.compact,
    required this.transparent,
    required this.hint,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final VoidCallback onSend;
  final bool compact;
  final bool transparent;
  final String hint;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(10, 6, 10, compact ? 6 : 10),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                onChanged: onChanged,
                onSubmitted: (_) => onSend(),
                textInputAction: TextInputAction.send,
                textCapitalization: TextCapitalization.sentences,
                minLines: 1,
                maxLines: 4,
                maxLength: 2000,
                decoration: InputDecoration(
                  hintText: hint,
                  counterText: '',
                  isDense: true,
                  fillColor: transparent ? Colors.black.withValues(alpha: 0.45) : DuetColors.surfaceHigh,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                  enabledBorder:
                      OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: const BorderSide(color: DuetColors.pink, width: 1.2),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: controller,
              builder: (context, value, _) {
                final enabled = value.text.trim().isNotEmpty;
                return AnimatedOpacity(
                  duration: const Duration(milliseconds: 150),
                  opacity: enabled ? 1 : 0.5,
                  child: Container(
                    decoration: const BoxDecoration(shape: BoxShape.circle, gradient: DuetColors.accentGradient),
                    child: IconButton(
                      onPressed: enabled ? onSend : null,
                      icon: const Icon(Icons.send_rounded, color: Colors.white, size: 20),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyChat extends StatelessWidget {
  const _EmptyChat({this.partnerName});

  final String? partnerName;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('💬', style: TextStyle(fontSize: 36)),
            const SizedBox(height: 8),
            Text(
              partnerName == null ? 'No messages yet' : 'Say hi to $partnerName',
              style: const TextStyle(color: DuetColors.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}

/// Full-screen chat (from the home screen).
class ChatScreen extends ConsumerWidget {
  const ChatScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final partner = ref.watch(sessionControllerProvider.select((s) => s.partner));
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Text(partner?.avatarEmoji ?? '💜', style: const TextStyle(fontSize: 22)),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(partner?.displayName ?? 'Chat', style: const TextStyle(fontSize: 17)),
                Text(
                  presenceText(partner),
                  style: TextStyle(
                    fontSize: 12,
                    color: partner?.online == true ? DuetColors.mint : DuetColors.textFaint,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      body: const DecoratedBox(
        decoration: BoxDecoration(gradient: DuetColors.backgroundGradient),
        child: ChatView(),
      ),
    );
  }
}
