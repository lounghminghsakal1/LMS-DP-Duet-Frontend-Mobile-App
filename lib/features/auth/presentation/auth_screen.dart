import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/server_config.dart';
import '../../../core/network/api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common.dart';
import 'auth_controller.dart';
import 'server_settings_sheet.dart';

const kAvatarEmojis = ['💜', '🌸', '🦋', '🐻', '🦊', '🐼', '🌙', '⭐', '🍓', '🧸', '🎧', '🍿', '🐱', '🐶', '🌻', '🔥'];

/// Sign in / create account. Email is the identity of each person.
class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController();
  bool _registerMode = false;
  bool _busy = false;
  bool _obscure = true;
  String _emoji = kAvatarEmojis.first;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    final auth = ref.read(authControllerProvider.notifier);
    try {
      if (_registerMode) {
        await auth.register(
          email: _email.text,
          password: _password.text,
          displayName: _name.text,
          avatarEmoji: _emoji,
        );
      } else {
        await auth.login(_email.text, _password.text);
      }
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final serverUrl = ref.watch(serverUrlProvider);
    final authState = ref.watch(authControllerProvider).value;
    final reason = authState is SignedOut ? authState.reason : null;

    return Scaffold(
      body: DuetBackground(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const _Logo(),
                      const SizedBox(height: 18),
                      Text(
                        _registerMode ? 'Create your account' : 'Welcome back',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Movies, songs and YouTube — together, in perfect sync.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: DuetColors.textMuted),
                      ),
                      const SizedBox(height: 28),
                      if (reason != null && _error == null) ...[
                        _Banner(text: reason, color: DuetColors.amber),
                        const SizedBox(height: 14),
                      ],
                      if (_error != null) ...[
                        _Banner(text: _error!, color: DuetColors.danger),
                        const SizedBox(height: 14),
                      ],
                      if (_registerMode) ...[
                        TextFormField(
                          controller: _name,
                          textCapitalization: TextCapitalization.words,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: 'Your name',
                            prefixIcon: Icon(Icons.person_rounded),
                          ),
                          validator: (v) => (v == null || v.trim().isEmpty) ? 'Tell us your name' : null,
                        ),
                        const SizedBox(height: 14),
                        _EmojiPicker(selected: _emoji, onSelected: (e) => setState(() => _emoji = e)),
                        const SizedBox(height: 14),
                      ],
                      TextFormField(
                        controller: _email,
                        keyboardType: TextInputType.emailAddress,
                        autocorrect: false,
                        textInputAction: TextInputAction.next,
                        autofillHints: const [AutofillHints.email],
                        decoration: const InputDecoration(
                          labelText: 'Email',
                          prefixIcon: Icon(Icons.alternate_email_rounded),
                        ),
                        validator: (v) {
                          final value = v?.trim() ?? '';
                          if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value)) {
                            return 'Enter a valid email';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _password,
                        obscureText: _obscure,
                        textInputAction: TextInputAction.done,
                        autofillHints: [_registerMode ? AutofillHints.newPassword : AutofillHints.password],
                        onFieldSubmitted: (_) => _submit(),
                        decoration: InputDecoration(
                          labelText: 'Password',
                          prefixIcon: const Icon(Icons.lock_rounded),
                          suffixIcon: IconButton(
                            icon: Icon(_obscure ? Icons.visibility_rounded : Icons.visibility_off_rounded),
                            onPressed: () => setState(() => _obscure = !_obscure),
                          ),
                        ),
                        validator: (v) {
                          final value = v ?? '';
                          if (value.isEmpty) return 'Enter your password';
                          if (_registerMode && value.length < 8) return 'Use at least 8 characters';
                          return null;
                        },
                      ),
                      const SizedBox(height: 24),
                      GradientButton(
                        label: _registerMode ? 'Create account' : 'Sign in',
                        loading: _busy,
                        onPressed: _submit,
                      ),
                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () => setState(() {
                                  _registerMode = !_registerMode;
                                  _error = null;
                                }),
                        child: Text(
                          _registerMode ? 'I already have an account' : "New here? Create an account",
                        ),
                      ),
                      const SizedBox(height: 18),
                      Center(
                        child: ActionChip(
                          avatar: const Icon(Icons.dns_rounded, size: 16, color: DuetColors.textMuted),
                          label: Text(
                            serverUrl,
                            style: const TextStyle(color: DuetColors.textMuted, fontSize: 12),
                          ),
                          backgroundColor: DuetColors.surface,
                          side: const BorderSide(color: DuetColors.outline),
                          onPressed: () => showServerSettingsSheet(context),
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

class _Logo extends StatelessWidget {
  const _Logo();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 84,
        height: 84,
        decoration: BoxDecoration(
          gradient: DuetColors.accentGradient,
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(color: DuetColors.pink.withValues(alpha: 0.4), blurRadius: 30, offset: const Offset(0, 12)),
          ],
        ),
        child: const Stack(
          alignment: Alignment.center,
          children: [
            Positioned(left: 16, child: Icon(Icons.favorite_rounded, color: Colors.white70, size: 34)),
            Positioned(right: 16, child: Icon(Icons.favorite_rounded, color: Colors.white, size: 34)),
          ],
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(text, style: TextStyle(color: color, fontWeight: FontWeight.w600)),
    );
  }
}

class _EmojiPicker extends StatelessWidget {
  const _EmojiPicker({required this.selected, required this.onSelected});

  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 4, bottom: 8),
          child: Text('Pick your avatar', style: TextStyle(color: DuetColors.textMuted)),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final emoji in kAvatarEmojis)
              GestureDetector(
                onTap: () => onSelected(emoji),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: emoji == selected ? DuetColors.pink.withValues(alpha: 0.2) : DuetColors.surfaceHigh,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: emoji == selected ? DuetColors.pink : Colors.transparent,
                      width: 1.5,
                    ),
                  ),
                  child: Text(emoji, style: const TextStyle(fontSize: 22)),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
