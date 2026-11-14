import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/prefs.dart';
import '../../../core/theme/app_mode.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../session/presentation/session_controller.dart';
import '../data/pairing_repository.dart';
import 'overview_controller.dart';

/// The theme the two of you share (general | love | friends).
///
/// The server is the source of truth: it arrives with /api/me and with every
/// room snapshot, so when your partner switches it your phone follows live.
/// The last value is cached per user so the app opens in the right theme.
class ModeController extends Notifier<AppMode> {
  String? _userId;

  String get _prefsKey => 'pair_mode_${_userId ?? 'anon'}';

  @override
  AppMode build() {
    _userId = ref.watch(currentUserIdProvider);
    if (_userId == null) return AppMode.general;

    // Live updates (and a fresh snapshot after every reconnect).
    ref.listen(sessionControllerProvider.select((s) => (s.roomLoaded, s.room?.mode)), (_, next) {
      final (loaded, mode) = next;
      if (mode != null) {
        _apply(mode);
      } else if (loaded) {
        _apply(AppMode.general); // not paired
      }
    });
    ref.listen(overviewControllerProvider.select((o) => o.value), (_, overview) {
      if (overview == null) return;
      _apply(overview.isPaired ? overview.mode ?? AppMode.general : AppMode.general);
    });

    return AppMode.parse(ref.read(sharedPreferencesProvider).getString(_prefsKey));
  }

  void _apply(AppMode mode) {
    if (!ref.mounted || state == mode) return;
    state = mode;
    ref.read(sharedPreferencesProvider).setString(_prefsKey, mode.name);
  }

  /// Switches the theme for both of you. Applied instantly, undone if the server refuses.
  Future<void> change(AppMode mode) async {
    final previous = state;
    _apply(mode);
    try {
      await ref.read(pairingRepositoryProvider).setMode(mode.name);
    } catch (_) {
      _apply(previous);
      rethrow;
    }
  }
}

final modeControllerProvider = NotifierProvider<ModeController, AppMode>(ModeController.new);
