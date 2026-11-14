import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/server_config.dart';
import '../../../core/theme/app_theme.dart';
import '../data/auth_repository.dart';

/// Lets the user point the app at their own server (laptop on Wi-Fi, or a deployed URL).
Future<void> showServerSettingsSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => const _ServerSettingsSheet(),
  );
}

class _ServerSettingsSheet extends ConsumerStatefulWidget {
  const _ServerSettingsSheet();

  @override
  ConsumerState<_ServerSettingsSheet> createState() => _ServerSettingsSheetState();
}

class _ServerSettingsSheetState extends ConsumerState<_ServerSettingsSheet> {
  late final TextEditingController _controller;
  bool? _reachable;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: ref.read(serverUrlProvider));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _test() async {
    setState(() {
      _checking = true;
      _reachable = null;
    });
    final ok = await AuthRepository.checkServer(normalizeServerUrl(_controller.text));
    if (!mounted) return;
    setState(() {
      _checking = false;
      _reachable = ok;
    });
  }

  Future<void> _save() async {
    await ref.read(serverUrlProvider.notifier).set(_controller.text);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(24, 0, 24, 24 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Server', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 6),
          const Text(
            'Both phones must use the same Duet server. Use your computer\'s Wi-Fi address '
            '(e.g. http://192.168.1.26:4747) or your deployed URL.',
            style: TextStyle(color: DuetColors.textMuted, height: 1.4),
          ),
          const SizedBox(height: 18),
          TextField(
            controller: _controller,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'Server address',
              prefixIcon: Icon(Icons.dns_rounded),
            ),
            onChanged: (_) => setState(() => _reachable = null),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              TextButton.icon(
                onPressed: _checking ? null : _test,
                icon: _checking
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.wifi_tethering_rounded),
                label: const Text('Test connection'),
              ),
              const SizedBox(width: 8),
              if (_reachable != null)
                Text(
                  _reachable! ? 'Reachable ✓' : 'Not reachable',
                  style: TextStyle(
                    color: _reachable! ? DuetColors.mint : DuetColors.danger,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              const Spacer(),
              TextButton(
                onPressed: () => _controller.text = kDefaultServerUrl,
                child: const Text('Default', style: TextStyle(color: DuetColors.textMuted)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          FilledButton(onPressed: _save, child: const Text('Save')),
        ],
      ),
    );
  }
}
