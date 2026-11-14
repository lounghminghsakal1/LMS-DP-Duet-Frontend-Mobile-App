import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/prefs.dart';
import '../../../core/theme/app_mode.dart';
import 'mode_controller.dart';

/// Android only: the home-screen icon follows the shared theme (General / Love /
/// Friends). The switch happens when you leave the app, because changing the
/// launcher entry while the app is open can close it on some phones.
///
/// State = whether the icon follows the theme (otherwise it stays General).
class AppIconController extends Notifier<bool> {
  static const _channel = MethodChannel('duet/app_icon');
  static const _prefsKey = 'app_icon_follows_theme';

  static bool get isSupported => !kIsWeb && Platform.isAndroid;

  @override
  bool build() {
    if (isSupported) {
      final lifecycle = AppLifecycleListener(onHide: _apply, onPause: _apply);
      ref.onDispose(lifecycle.dispose);
    }
    return ref.read(sharedPreferencesProvider).getBool(_prefsKey) ?? true;
  }

  AppMode get _wanted => state ? ref.read(modeControllerProvider) : AppMode.general;

  Future<void> _apply() async {
    if (!isSupported || !ref.mounted) return;
    try {
      await _channel.invokeMethod<bool>('set', {'name': _wanted.name});
    } catch (error) {
      debugPrint('Could not switch the app icon: $error');
    }
  }

  Future<void> setFollowTheme(bool follow) async {
    await ref.read(sharedPreferencesProvider).setBool(_prefsKey, follow);
    state = follow;
  }
}

final appIconControllerProvider = NotifierProvider<AppIconController, bool>(AppIconController.new);
