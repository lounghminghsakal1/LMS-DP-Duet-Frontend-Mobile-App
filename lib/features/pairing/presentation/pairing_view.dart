import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/format.dart';
import '../../../core/widgets/common.dart';
import '../domain/overview.dart';
import 'overview_controller.dart';

/// Shown until the two of you are paired: invite your partner by email or accept their invite.
class PairingView extends ConsumerStatefulWidget {
  const PairingView({super.key, required this.overview});

  final Overview overview;

  @override
  ConsumerState<PairingView> createState() => _PairingViewState();
}

class _PairingViewState extends ConsumerState<PairingView> {
  final _email = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } on ApiException catch (error) {
      if (mounted) showToast(context, error.message, icon: Icons.error_outline_rounded);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _invite() async {
    final email = _email.text.trim();
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
      showToast(context, 'Enter your partner\'s email address');
      return;
    }
    FocusScope.of(context).unfocus();
    await _run(() async {
      final paired = await ref.read(overviewControllerProvider.notifier).invite(email);
      if (!mounted) return;
      _email.clear();
      showToast(context, paired ? context.copy.pairedToast : 'Invite sent to $email', icon: Icons.check_circle_rounded);
    });
  }

  @override
  Widget build(BuildContext context) {
    final overview = widget.overview;
    final controller = ref.read(overviewControllerProvider.notifier);

    return RefreshIndicator(
      onRefresh: controller.refresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          const SizedBox(height: 12),
          Center(child: Text(context.copy.pairEmoji, style: const TextStyle(fontSize: 56))),
          const SizedBox(height: 12),
          Text(
            context.copy.pairTitle,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          const Text(
            'Enter the email they use (or will use) for Duet. As soon as they accept, '
            'you can watch and listen together.',
            textAlign: TextAlign.center,
            style: TextStyle(color: DuetColors.textMuted, height: 1.4),
          ),
          const SizedBox(height: 24),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  EmojiAvatar(emoji: overview.user.avatarEmoji, size: 42),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(overview.user.displayName, style: const TextStyle(fontWeight: FontWeight.w700)),
                        Text(overview.user.email, style: const TextStyle(color: DuetColors.textMuted, fontSize: 13)),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Copy my email',
                    icon: const Icon(Icons.copy_rounded, size: 20),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: overview.user.email));
                      showToast(context, 'Email copied — send it to your partner');
                    },
                  ),
                ],
              ),
            ),
          ),
          if (overview.incoming.isNotEmpty) ...[
            const SizedBox(height: 24),
            const SectionTitle('Invites for you'),
            for (final invite in overview.incoming)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _IncomingInviteCard(
                  invite: invite,
                  busy: _busy,
                  onAccept: () => _run(() => controller.accept(invite.id)),
                  onDecline: () => _run(() => controller.decline(invite.id)),
                ),
              ),
          ],
          const SizedBox(height: 24),
          if (overview.outgoing != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                        SizedBox(width: 10),
                        Text('Waiting for them to accept', style: TextStyle(fontWeight: FontWeight.w700)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Invite sent to ${overview.outgoing!.toEmail} · ${formatRelative(overview.outgoing!.createdAt)}',
                      style: const TextStyle(color: DuetColors.textMuted),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'They\'ll see it as soon as they open Duet with that email.',
                      style: TextStyle(color: DuetColors.textFaint, fontSize: 13),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: _busy ? null : () => _run(() => controller.cancel(overview.outgoing!.id)),
                        child: const Text('Cancel invite'),
                      ),
                    ),
                  ],
                ),
              ),
            )
          else ...[
            TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _invite(),
              decoration: InputDecoration(
                labelText: context.copy.inviteLabel,
                prefixIcon: Icon(Icons.person_add_alt_rounded),
              ),
            ),
            const SizedBox(height: 14),
            GradientButton(label: 'Send invite', icon: Icons.send_rounded, loading: _busy, onPressed: _invite),
          ],
        ],
      ),
    );
  }
}

class _IncomingInviteCard extends StatelessWidget {
  const _IncomingInviteCard({
    required this.invite,
    required this.busy,
    required this.onAccept,
    required this.onDecline,
  });

  final PairInvite invite;
  final bool busy;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    final from = invite.from;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          colors: [context.palette.accent.withValues(alpha: 0.18), context.palette.accent2.withValues(alpha: 0.18)],
        ),
        border: Border.all(color: context.palette.accent.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              EmojiAvatar(emoji: from?.avatarEmoji ?? '💜', size: 42),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${from?.displayName ?? 'Someone'} wants to pair with you',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    if (from != null)
                      Text(from.email, style: const TextStyle(color: DuetColors.textMuted, fontSize: 13)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(onPressed: busy ? null : onDecline, child: const Text('Decline')),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                  onPressed: busy ? null : onAccept,
                  child: Text(context.copy.acceptLabel),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
