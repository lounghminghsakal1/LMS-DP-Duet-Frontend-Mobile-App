import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/theme/app_theme.dart';
import '../core/widgets/common.dart';
import '../features/auth/presentation/auth_controller.dart';
import '../features/auth/presentation/auth_screen.dart';
import '../features/chat/presentation/chat_view.dart';
import '../features/history/presentation/history_screen.dart';
import '../features/home/presentation/home_screen.dart';
import '../features/library/presentation/media_picker_screen.dart';
import '../features/player/presentation/join_screen.dart';
import '../features/player/presentation/watch_flow.dart';
import '../features/player/presentation/watch_screen.dart';
import '../features/player/presentation/youtube_entry_screen.dart';
import '../features/profile/presentation/profile_screen.dart';
import '../features/session/domain/room_state.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier<int>(0);
  ref.listen(authControllerProvider, (_, _) => refresh.value++);

  final router = GoRouter(
    initialLocation: '/',
    refreshListenable: refresh,
    redirect: (context, state) {
      final auth = ref.read(authControllerProvider);
      final location = state.matchedLocation;
      if (auth.isLoading && !auth.hasValue) {
        return location == '/splash' ? null : '/splash';
      }
      final signedIn = auth.value is SignedIn;
      if (!signedIn) return location == '/auth' ? null : '/auth';
      if (location == '/auth' || location == '/splash') return '/';
      return null;
    },
    routes: [
      GoRoute(path: '/splash', builder: (_, _) => const _SplashScreen()),
      GoRoute(path: '/auth', builder: (_, _) => const AuthScreen()),
      GoRoute(path: '/', builder: (_, _) => const HomeScreen()),
      GoRoute(path: '/chat', builder: (_, _) => const ChatScreen()),
      GoRoute(path: '/history', builder: (_, _) => const HistoryScreen()),
      GoRoute(path: '/profile', builder: (_, _) => const ProfileScreen()),
      GoRoute(path: '/youtube', builder: (_, _) => const YoutubeEntryScreen()),
      GoRoute(path: '/join', builder: (_, _) => const JoinScreen()),
      GoRoute(
        path: '/pick/:kind',
        builder: (_, state) => MediaPickerScreen(
          kind: MediaKind.parse(state.pathParameters['kind'] ?? 'video'),
          hint: state.uri.queryParameters['hint'],
        ),
      ),
      GoRoute(
        path: '/watch',
        redirect: (_, state) => state.extra is WatchArgs ? null : '/',
        builder: (_, state) => WatchScreen(args: state.extra! as WatchArgs),
      ),
    ],
  );

  ref.onDispose(() {
    router.dispose();
    refresh.dispose();
  });
  return router;
});

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: DuetBackground(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.favorite_rounded, color: DuetColors.pink, size: 56),
              SizedBox(height: 18),
              SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4)),
            ],
          ),
        ),
      ),
    );
  }
}
