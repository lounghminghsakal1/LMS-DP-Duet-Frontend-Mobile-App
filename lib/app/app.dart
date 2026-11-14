import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/theme/app_theme.dart';
import '../features/chat/presentation/chat_controller.dart';
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

  @override
  void initState() {
    super.initState();
    _sub = ref.read(sessionEventsProvider).stream.listen(_onEvent);
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
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
      case ServerErrorReceived(:final code, :final message) when code == 'partner_offline' || code == 'not_paired':
        _snack(message);
      default:
        break;
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
