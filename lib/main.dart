import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/app.dart';
import 'core/network/api_client.dart';
import 'core/storage/prefs.dart';
import 'features/auth/presentation/auth_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();

  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Color(0xFF0E0A1C),
    ),
  );

  runApp(
    ProviderScope(
      // Failed loads are handled in the UI (retry buttons), no silent auto-retry.
      retry: (_, _) => null,
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        unauthorizedCallbackProvider.overrideWith(
          (ref) => () => ref.read(authControllerProvider.notifier).handleUnauthorized(),
        ),
      ],
      child: const DuetApp(),
    ),
  );
}
