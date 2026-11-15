import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Full-screen gradient background used behind most screens.
class DuetBackground extends StatelessWidget {
  const DuetBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(gradient: context.palette.backgroundGradient),
      child: child,
    );
  }
}

/// Emoji avatar with an optional online indicator.
class EmojiAvatar extends StatelessWidget {
  const EmojiAvatar({
    super.key,
    required this.emoji,
    this.size = 44,
    this.online,
    this.gradient,
  });

  final String emoji;
  final double size;
  final bool? online;
  /// Defaults to the current theme's accent gradient.
  final Gradient? gradient;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(shape: BoxShape.circle, gradient: gradient ?? context.palette.accentGradient),
            padding: const EdgeInsets.all(2),
            child: Container(
              decoration: BoxDecoration(shape: BoxShape.circle, color: context.palette.surfaceHigh),
              alignment: Alignment.center,
              child: Text(emoji, style: TextStyle(fontSize: size * 0.46)),
            ),
          ),
          if (online != null)
            Positioned(
              right: -1,
              bottom: -1,
              child: Container(
                width: size * 0.3,
                height: size * 0.3,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: online! ? DuetColors.mint : DuetColors.textFaint,
                  border: Border.all(color: context.palette.background, width: 2),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(color: DuetColors.text),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// Small rounded "pill" label.
class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.label, this.color = DuetColors.textMuted, this.icon});

  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: color.withValues(alpha: 0.35), width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 5),
          ],
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

/// Gradient filled button.
class GradientButton extends StatelessWidget {
  const GradientButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.loading = false,
    this.gradient,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool loading;
  /// Defaults to the current theme's accent gradient.
  final Gradient? gradient;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !loading;
    return Opacity(
      opacity: enabled ? 1 : 0.6,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: gradient ?? context.palette.accentGradient,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(color: context.palette.accent.withValues(alpha: 0.25), blurRadius: 18, offset: const Offset(0, 8)),
          ],
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: enabled ? onPressed : null,
            child: SizedBox(
              height: 54,
              child: Center(
                child: loading
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                      )
                    : Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (icon != null) ...[
                              Icon(icon, color: Colors.white, size: 20),
                              const SizedBox(width: 8),
                            ],
                            // Long labels (e.g. long names) shrink with "…" instead of overflowing.
                            Flexible(
                              child: Text(
                                label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16),
                              ),
                            ),
                          ],
                        ),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

void showToast(BuildContext context, String message, {IconData? icon}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 3),
        content: Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: 18, color: context.palette.accent),
              const SizedBox(width: 10),
            ],
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
}

Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Yes',
  String cancelLabel = 'Cancel',
  bool destructive = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message, style: const TextStyle(color: DuetColors.textMuted)),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(cancelLabel, style: const TextStyle(color: DuetColors.textMuted)),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(
            confirmLabel,
            style: TextStyle(color: destructive ? DuetColors.danger : context.palette.accent, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    ),
  );
  return result ?? false;
}
