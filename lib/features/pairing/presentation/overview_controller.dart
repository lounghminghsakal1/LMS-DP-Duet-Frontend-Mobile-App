import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/presentation/auth_controller.dart';
import '../../session/data/session_client.dart';
import '../../session/presentation/session_controller.dart';
import '../data/pairing_repository.dart';
import '../domain/overview.dart';

class OverviewController extends AsyncNotifier<Overview> {
  PairingRepository get _repo => ref.read(pairingRepositoryProvider);

  @override
  Future<Overview> build() async {
    ref.watch(currentUserIdProvider);
    // Refresh whenever the server tells us pairing changed (invite received, accepted, …).
    final sub = ref.read(sessionEventsProvider).stream.listen((event) {
      if (event is PairingChanged) refresh();
    });
    ref.onDispose(sub.cancel);
    return _load();
  }

  Future<Overview> _load() async {
    final overview = await _repo.overview();
    // Keep the cached profile's couple id in sync (the socket uses it on reconnect).
    final current = ref.read(currentUserProvider);
    if (current != null && current.coupleId != overview.user.coupleId) {
      unawaited(ref.read(authControllerProvider.notifier).updateUser(overview.user));
    }
    return overview;
  }

  Future<void> refresh() async {
    final next = await AsyncValue.guard(_load);
    if (!ref.mounted) return;
    // Keep showing old data if a background refresh fails.
    if (next.hasError && state.hasValue) return;
    state = next;
  }

  Future<bool> invite(String email) async {
    final paired = await _repo.invite(email);
    await refresh();
    return paired;
  }

  Future<void> accept(String inviteId) async {
    await _repo.accept(inviteId);
    await refresh();
  }

  Future<void> decline(String inviteId) async {
    await _repo.decline(inviteId);
    await refresh();
  }

  Future<void> cancel(String inviteId) async {
    await _repo.cancel(inviteId);
    await refresh();
  }

  Future<void> unpair() async {
    await _repo.unpair();
    await refresh();
  }
}

final overviewControllerProvider = AsyncNotifierProvider<OverviewController, Overview>(OverviewController.new);
