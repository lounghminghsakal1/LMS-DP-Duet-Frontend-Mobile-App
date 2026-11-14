import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/server_config.dart';
import '../../../core/network/api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common.dart';
import '../../auth/data/auth_repository.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../auth/presentation/auth_screen.dart' show kAvatarEmojis;
import '../../auth/presentation/server_settings_sheet.dart';
import '../../pairing/presentation/overview_controller.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  Future<void> _editName(BuildContext context, WidgetRef ref, String current) async {
    final controller = TextEditingController(text: current);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Your name'),
        content: TextField(controller: controller, autofocus: true, maxLength: 40),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('Save')),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.isEmpty || name == current || !context.mounted) return;
    await _update(context, ref, displayName: name);
  }

  Future<void> _pickEmoji(BuildContext context, WidgetRef ref) async {
    final emoji = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
        child: Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final e in kAvatarEmojis)
              InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => Navigator.pop(context, e),
                child: Container(
                  width: 52,
                  height: 52,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: DuetColors.surfaceHigh, borderRadius: BorderRadius.circular(14)),
                  child: Text(e, style: const TextStyle(fontSize: 26)),
                ),
              ),
          ],
        ),
      ),
    );
    if (emoji == null || !context.mounted) return;
    await _update(context, ref, avatarEmoji: emoji);
  }

  Future<void> _update(BuildContext context, WidgetRef ref, {String? displayName, String? avatarEmoji}) async {
    try {
      final user = await ref.read(authRepositoryProvider).updateProfile(displayName: displayName, avatarEmoji: avatarEmoji);
      await ref.read(authControllerProvider.notifier).updateUser(user);
      ref.read(overviewControllerProvider.notifier).refresh();
    } on ApiException catch (error) {
      if (context.mounted) showToast(context, error.message);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final overview = ref.watch(overviewControllerProvider).value;
    final partner = overview?.partner;
    final server = ref.watch(serverUrlProvider);
    if (user == null) return const Scaffold();

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: DuetBackground(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Center(
              child: GestureDetector(
                onTap: () => _pickEmoji(context, ref),
                child: Stack(
                  children: [
                    EmojiAvatar(emoji: user.avatarEmoji, size: 96),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: const BoxDecoration(shape: BoxShape.circle, color: DuetColors.pink),
                        child: const Icon(Icons.edit_rounded, size: 14, color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Center(child: Text(user.displayName, style: Theme.of(context).textTheme.headlineSmall)),
            Center(child: Text(user.email, style: const TextStyle(color: DuetColors.textMuted))),
            const SizedBox(height: 24),
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.badge_rounded),
                    title: const Text('Name'),
                    subtitle: Text(user.displayName),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => _editName(context, ref, user.displayName),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.dns_rounded),
                    title: const Text('Server'),
                    subtitle: Text(server),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => showServerSettingsSheet(context),
                  ),
                ],
              ),
            ),
            if (partner != null) ...[
              const SizedBox(height: 16),
              Card(
                child: Column(
                  children: [
                    ListTile(
                      leading: Text(partner.avatarEmoji, style: const TextStyle(fontSize: 24)),
                      title: Text('Paired with ${partner.displayName}'),
                      subtitle: Text(partner.email),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.heart_broken_rounded, color: DuetColors.danger),
                      title: const Text('Unpair', style: TextStyle(color: DuetColors.danger)),
                      subtitle: const Text('Also deletes your shared chat history'),
                      onTap: () async {
                        final ok = await confirmDialog(
                          context,
                          title: 'Unpair from ${partner.displayName}?',
                          message: 'Your shared chat will be deleted for both of you. Watch history on each phone stays.',
                          confirmLabel: 'Unpair',
                          destructive: true,
                        );
                        if (!ok) return;
                        try {
                          await ref.read(overviewControllerProvider.notifier).unpair();
                          if (context.mounted) Navigator.of(context).pop();
                        } on ApiException catch (error) {
                          if (context.mounted) showToast(context, error.message);
                        }
                      },
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.logout_rounded),
                    title: const Text('Sign out'),
                    onTap: () => ref.read(authControllerProvider.notifier).signOut(),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.devices_other_rounded),
                    title: const Text('Sign out on all devices'),
                    onTap: () async {
                      final ok = await confirmDialog(
                        context,
                        title: 'Sign out everywhere?',
                        message: 'Every phone signed in to your account will be signed out.',
                        confirmLabel: 'Sign out',
                        destructive: true,
                      );
                      if (ok) {
                        try {
                          await ref.read(authControllerProvider.notifier).signOutEverywhere();
                        } on ApiException catch (error) {
                          if (context.mounted) showToast(context, error.message);
                        }
                      }
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            const Center(
              child: Text(
                'Duet · movies & songs stay on your phones, never uploaded',
                style: TextStyle(color: DuetColors.textFaint, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
