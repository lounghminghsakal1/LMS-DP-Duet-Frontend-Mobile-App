import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/theme/app_theme.dart';
import '../core/utils/format.dart';
import '../features/chat/presentation/chat_controller.dart';
import '../features/sharing/presentation/share_controller.dart';
import '../features/session/data/session_client.dart';
import '../features/session/presentation/session_controller.dart';
import 'router.dart';

final scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

class DuetApp extends ConsumerWidget {
  const DuetApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    // Keep the realtime connection and chat alive for the whole app.
    ref.watch(sessionControllerProvider.select((s) => s.connection));
    ref.listen(chatControllerProvider.select((c) => c.unread), (_, _) {});

    return MaterialApp.router(
      title: 'Duet',
      debugShowCheckedModeBanner: false,
      theme: buildDuetTheme(),
      darkTheme: buildDuetTheme(),
      themeMode: ThemeMode.dark,
      scaffoldMessengerKey: scaffoldMessengerKey,
      routerConfig: router,
      builder: (context, child) => _GlobalSessionListener(router: router, child: child ?? const SizedBox()),
    );
  }
}

/// App-wide reactions to realtime events: love taps (with a heart burst) and
/// "your partner started something — join?" wherever you are in the app.
class _GlobalSessionListener extends ConsumerStatefulWidget {
  const _GlobalSessionListener({required this.router, required this.child});

  final GoRouter router;
  final Widget child;

  @override
  ConsumerState<_GlobalSessionListener> createState() => _GlobalSessionListenerState();
}

class _GlobalSessionListenerState extends ConsumerState<_GlobalSessionListener> {
  StreamSubscription<SessionEvent>? _sub;
  final _bursts = <int>[];
  int _nextBurst = 0;
  Timer? _offlineTimer;
  bool _announcedOffline = false;

  @override
  void initState() {
    super.initState();
    _sub = ref.read(sessionEventsProvider).stream.listen(_onEvent);
  }

  @override
  void dispose() {
    _sub?.cancel();
    _offlineTimer?.cancel();
    super.dispose();
  }

  /// "Sam went offline" / "Sam is back online" outside the player (the player has
  /// its own popup). Waits a few seconds so short network blips don't spam you.
  void _onPresence(bool online) {
    _offlineTimer?.cancel();
    if (!online) {
      _offlineTimer = Timer(const Duration(seconds: 5), () {
        final partner = ref.read(sessionControllerProvider).partner;
        if (partner == null || partner.online || _currentPath == '/watch') return;
        _announcedOffline = true;
        _snack('⚫  ${partner.displayName} went offline');
      });
    } else if (_announcedOffline) {
      _announcedOffline = false;
      final partner = ref.read(sessionControllerProvider).partner;
      if (_currentPath != '/watch') _snack('💚  ${partner?.displayName ?? 'Your partner'} is back online');
    }
  }

  String get _currentPath {
    try {
      return widget.router.routerDelegate.currentConfiguration.uri.path;
    } catch (_) {
      return '/';
    }
  }

  void _onEvent(SessionEvent event) {
    final session = ref.read(sessionControllerProvider);
    final partnerName = session.partner?.displayName ?? 'Your partner';
    switch (event) {
      case NudgeReceived(:final kind):
        HapticFeedback.heavyImpact();
        Future<void>.delayed(const Duration(milliseconds: 180), HapticFeedback.heavyImpact);
        final (emoji, text) = switch (kind) {
          'hug' => ('🤗', '$partnerName sent you a hug'),
          'kiss' => ('💋', '$partnerName sent you a kiss'),
          'miss_you' => ('🥺', '$partnerName misses you'),
          'come_watch' => ('🍿', '$partnerName says: come watch with me!'),
          _ => ('💞', '$partnerName is thinking of you'),
        };
        _burst();
        _snack('$emoji  $text', action: kind == 'come_watch' && session.media != null ? _joinAction() : null);
      case RoomEventReceived(:final event, :final room)
          when event.kind == 'media_loaded' && event.by != session.myUserId:
        final path = _currentPath;
        if (path == '/watch' || path == '/join' || room?.media == null) return;
        final media = room!.media!;
        _snack(
          '${media.kind.emoji}  $partnerName started “${media.title}”',
          action: _joinAction(),
          duration: const Duration(seconds: 8),
        );
      case RoomEventReceived(:final event) when event.kind == 'presence' && event.userId != session.myUserId:
        _onPresence(event.online == true);
      case ShareRequested():
        _askToShare();
      case ServerErrorReceived(:final code, :final message) when code == 'partner_offline' || code == 'not_paired':
        _snack(message);
      default:
        break;
    }
  }

  /// The partner doesn't have the current movie: offer to upload it temporarily.
  Future<void> _askToShare() async {
    final session = ref.read(sessionControllerProvider);
    final media = session.media;
    final dialogContext = widget.router.routerDelegate.navigatorKey.currentContext;
    if (media == null || dialogContext == null) return;
    final client = ref.read(sessionControllerProvider.notifier).client;
    if (ref.read(shareControllerProvider).isBusy) return;
    final partnerName = session.partner?.displayName ?? 'Your partner';
    final size = media.sizeBytes != null && media.sizeBytes! > 1 ? ' (${formatBytes(media.sizeBytes!)})' : '';

    final share = await showDialog<bool>(
      context: dialogContext,
      builder: (context) => AlertDialog(
        icon: const Text('📤', style: TextStyle(fontSize: 34)),
        title: Text('Share “${media.title}” with $partnerName?'),
        content: Text(
          '$partnerName doesn\'t have this file. Duet will upload your copy$size so they can stream it '
          'while you watch together.\n\n'
          '• It\'s private and deleted automatically when you finish.\n'
          '• It uses your internet — Wi-Fi is best.\n'
          '• Keep Duet open until the upload finishes.',
          style: const TextStyle(color: DuetColors.textMuted, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Not now', style: TextStyle(color: DuetColors.textMuted)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(110, 44)),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Share it'),
          ),
        ],
      ),
    );
    if (share == true) {
      ref.read(shareControllerProvider.notifier).shareCurrent();
    } else {
      client?.declineShare();
    }
  }

  SnackBarAction _joinAction() => SnackBarAction(
        label: 'JOIN',
        textColor: DuetColors.pink,
        onPressed: () => widget.router.push('/join'),
      );

  void _snack(String text, {SnackBarAction? action, Duration duration = const Duration(seconds: 4)}) {
    scaffoldMessengerKey.currentState
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text), action: action, duration: duration));
  }

  void _burst() {
    final id = _nextBurst++;
    setState(() => _bursts.add(id));
    Future<void>.delayed(const Duration(milliseconds: 1800), () {
      if (mounted) setState(() => _bursts.remove(id));
    });
  }

  @override
  Widget build(BuildContext context) {
    // Upload outcome notifications (the uploader may be on any screen).
    ref.listen(shareControllerProvider.select((s) => s.status), (previous, status) {
      final state = ref.read(shareControllerProvider);
      final partnerName = ref.read(sessionControllerProvider).partner?.displayName ?? 'your partner';
      if (status == ShareUploadStatus.done && previous == ShareUploadStatus.uploading) {
        _snack('🎉  Uploaded — $partnerName can watch “${state.title}” now');
      } else if (status == ShareUploadStatus.failed && state.error != null) {
        _snack('⚠️  ${state.error}', duration: const Duration(seconds: 6));
      }
    });

    return Stack(
      children: [
        widget.child,
        for (final id in _bursts) Positioned.fill(child: _HeartBurst(key: ValueKey(id))),
      ],
    );
  }
}

/// A ring of hearts bursting from the middle of the screen.
class _HeartBurst extends StatefulWidget {
  const _HeartBurst({super.key});

  @override
  State<_HeartBurst> createState() => _HeartBurstState();
}

class _HeartBurstState extends State<_HeartBurst> with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))..forward();
  final _random = math.Random();
  late final List<(double angle, double distance, double size)> _hearts = List.generate(
    14,
    (i) => (i / 14 * math.pi * 2 + _random.nextDouble() * 0.3, 90 + _random.nextDouble() * 90, 22 + _random.nextDouble() * 18),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final t = Curves.easeOutCubic.transform(_controller.value);
          final fade = (1 - _controller.value).clamp(0.0, 1.0);
          return Stack(
            alignment: Alignment.center,
            children: [
              Opacity(
                opacity: fade,
                child: Transform.scale(
                  scale: 0.6 + t * 0.8,
                  child: const Icon(Icons.favorite_rounded, color: DuetColors.pink, size: 90),
                ),
              ),
              for (final (angle, distance, size) in _hearts)
                Transform.translate(
                  offset: Offset(math.cos(angle) * distance * t, math.sin(angle) * distance * t),
                  child: Opacity(
                    opacity: fade,
                    child: Text('💗', style: TextStyle(fontSize: size)),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
