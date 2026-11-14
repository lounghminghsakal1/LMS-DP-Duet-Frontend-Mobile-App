import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/theme/app_mode.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/duet_logo.dart';
import '../../session/presentation/session_controller.dart';
import 'app_icon_controller.dart';
import 'mode_controller.dart';

/// "Theme for both of you": General / Love / Friends. Changes both phones.
Future<void> showThemePicker(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => const _ThemePickerSheet(),
  );
}

class _ThemePickerSheet extends ConsumerStatefulWidget {
  const _ThemePickerSheet();

  @override
  ConsumerState<_ThemePickerSheet> createState() => _ThemePickerSheetState();
}

class _ThemePickerSheetState extends ConsumerState<_ThemePickerSheet> {
  bool _busy = false;

  Future<void> _choose(AppMode mode) async {
    if (_busy || mode == ref.read(modeControllerProvider)) {
      Navigator.of(context).pop();
      return;
    }
    setState(() => _busy = true);
    final partnerName = ref.read(sessionControllerProvider).partner?.displayName;
    try {
      await ref.read(modeControllerProvider.notifier).change(mode);
      if (!mounted) return;
      final copy = ModeCopy(mode);
      showToast(
        context,
        '${copy.emoji}  ${copy.label} theme on${partnerName != null ? ' for you and $partnerName' : ''}',
      );
      Navigator.of(context).pop();
    } on ApiException catch (error) {
      if (mounted) showToast(context, error.message, icon: Icons.error_outline_rounded);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = ref.watch(modeControllerProvider);
    final partner = ref.watch(sessionControllerProvider.select((s) => s.partner));

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Theme for both of you', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              [
                partner == null ? 'Pick how Duet looks and feels.' : 'Changes on ${partner.displayName}\'s phone too.',
                if (AppIconController.isSupported && ref.watch(appIconControllerProvider))
                  'The app icon changes to match when you leave the app.',
              ].join(' '),
              style: const TextStyle(color: DuetColors.textMuted),
            ),
            const SizedBox(height: 18),
            for (final mode in AppMode.values) ...[
              _ModeOption(
                mode: mode,
                selected: mode == current,
                busy: _busy,
                onTap: () => _choose(mode),
              ),
              const SizedBox(height: 12),
            ],
          ],
        ),
      ),
    );
  }
}

class _ModeOption extends StatelessWidget {
  const _ModeOption({required this.mode, required this.selected, required this.busy, required this.onTap});

  final AppMode mode;
  final bool selected;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = DuetPalette.of(mode);
    final copy = ModeCopy(mode);
    return Material(
      color: palette.surface,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: busy ? null : onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: selected ? palette.accent : palette.outline, width: selected ? 2 : 0.8),
          ),
          child: Row(
            children: [
              DuetLogo(mode: mode, size: 58),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(copy.label, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                    const SizedBox(height: 3),
                    Text(copy.description, style: const TextStyle(color: DuetColors.textMuted, fontSize: 13)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        for (final tap in copy.taps.take(3))
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: Text(tap.emoji, style: const TextStyle(fontSize: 16)),
                          ),
                        const SizedBox(width: 4),
                        for (final color in [palette.accent, palette.accent2, palette.quote])
                          Container(
                            width: 12,
                            height: 12,
                            margin: const EdgeInsets.only(right: 4),
                            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              if (selected) Icon(Icons.check_circle_rounded, color: palette.accent),
            ],
          ),
        ),
      ),
    );
  }
}
