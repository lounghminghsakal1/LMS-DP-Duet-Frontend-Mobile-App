import 'package:flutter/material.dart';

import 'app_mode.dart';

/// Colours shared by every theme: text and status.
abstract final class DuetColors {
  static const text = Color(0xFFF3F4F8);
  static const textMuted = Color(0xFFAAB0C4);
  static const textFaint = Color(0xFF747B93);
  static const mint = Color(0xFF4ADE9B);
  static const amber = Color(0xFFFFC857);
  static const danger = Color(0xFFFF6B6B);
}

/// The mode-dependent part of the theme. It's a [ThemeExtension], so switching
/// mode animates every colour and gradient smoothly across the whole app.
/// Read it with `context.palette` (and wording with `context.copy`).
@immutable
class DuetPalette extends ThemeExtension<DuetPalette> {
  const DuetPalette({
    required this.mode,
    required this.accent,
    required this.accent2,
    required this.quote,
    required this.background,
    required this.surface,
    required this.surfaceHigh,
    required this.outline,
    required this.accentGradient,
    required this.movieGradient,
    required this.musicGradient,
    required this.youtubeGradient,
    required this.backgroundGradient,
  });

  final AppMode mode;

  /// Main accent (buttons, highlights, my chat bubbles).
  final Color accent;

  /// Secondary accent.
  final Color accent2;

  /// Colour of quoted-reply names.
  final Color quote;
  final Color background;
  final Color surface;
  final Color surfaceHigh;
  final Color outline;
  final LinearGradient accentGradient;
  final LinearGradient movieGradient;
  final LinearGradient musicGradient;
  final LinearGradient youtubeGradient;
  final LinearGradient backgroundGradient;

  ModeCopy get copy => ModeCopy(mode);

  static const _tl = Alignment.topLeft;
  static const _br = Alignment.bottomRight;

  /// Default: a neutral "cinema" blue, for anyone.
  static const general = DuetPalette(
    mode: AppMode.general,
    accent: Color(0xFF4C8DFF),
    accent2: Color(0xFF22C7E6),
    quote: Color(0xFF7DD3FC),
    background: Color(0xFF0B0F1A),
    surface: Color(0xFF141A2A),
    surfaceHigh: Color(0xFF1D2539),
    outline: Color(0xFF2C3650),
    accentGradient: LinearGradient(colors: [Color(0xFF4C8DFF), Color(0xFF6A5CFF)], begin: _tl, end: _br),
    movieGradient: LinearGradient(colors: [Color(0xFF3B82F6), Color(0xFF1E40AF)], begin: _tl, end: _br),
    musicGradient: LinearGradient(colors: [Color(0xFF14B8A6), Color(0xFF0E7490)], begin: _tl, end: _br),
    youtubeGradient: LinearGradient(colors: [Color(0xFFFF6B4A), Color(0xFFE11D48)], begin: _tl, end: _br),
    backgroundGradient: LinearGradient(
      colors: [Color(0xFF111A2E), Color(0xFF0B0F1A), Color(0xFF070A12)],
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      stops: [0, 0.45, 1],
    ),
  );

  /// Romantic pink → violet.
  static const love = DuetPalette(
    mode: AppMode.love,
    accent: Color(0xFFFF5E8A),
    accent2: Color(0xFF8B5CF6),
    quote: Color(0xFFFFB37A),
    background: Color(0xFF0E0A1C),
    surface: Color(0xFF19132E),
    surfaceHigh: Color(0xFF241C40),
    outline: Color(0xFF3A2F5F),
    accentGradient: LinearGradient(colors: [Color(0xFFFF5E8A), Color(0xFF8B5CF6)], begin: _tl, end: _br),
    movieGradient: LinearGradient(colors: [Color(0xFFFF5E8A), Color(0xFFB0447A)], begin: _tl, end: _br),
    musicGradient: LinearGradient(colors: [Color(0xFF8B5CF6), Color(0xFF4F46E5)], begin: _tl, end: _br),
    youtubeGradient: LinearGradient(colors: [Color(0xFFFF7A59), Color(0xFFE11D48)], begin: _tl, end: _br),
    backgroundGradient: LinearGradient(
      colors: [Color(0xFF1A1033), Color(0xFF0E0A1C), Color(0xFF0A0716)],
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      stops: [0, 0.45, 1],
    ),
  );

  /// Playful tangerine + teal.
  static const friends = DuetPalette(
    mode: AppMode.friends,
    accent: Color(0xFFFF7A45),
    accent2: Color(0xFF2EC4B6),
    quote: Color(0xFFFFD166),
    background: Color(0xFF0B1415),
    surface: Color(0xFF13201F),
    surfaceHigh: Color(0xFF1B2D2C),
    outline: Color(0xFF2B4442),
    accentGradient: LinearGradient(colors: [Color(0xFFFF7A45), Color(0xFFFFA43D)], begin: _tl, end: _br),
    movieGradient: LinearGradient(colors: [Color(0xFFFF7A45), Color(0xFFE2553A)], begin: _tl, end: _br),
    musicGradient: LinearGradient(colors: [Color(0xFF2EC4B6), Color(0xFF178A80)], begin: _tl, end: _br),
    youtubeGradient: LinearGradient(colors: [Color(0xFFFF5E5E), Color(0xFFE11D48)], begin: _tl, end: _br),
    backgroundGradient: LinearGradient(
      colors: [Color(0xFF10241F), Color(0xFF0B1415), Color(0xFF070D0E)],
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      stops: [0, 0.45, 1],
    ),
  );

  static DuetPalette of(AppMode mode) => switch (mode) {
        AppMode.general => general,
        AppMode.love => love,
        AppMode.friends => friends,
      };

  @override
  DuetPalette copyWith({AppMode? mode}) => mode == null ? this : of(mode);

  @override
  DuetPalette lerp(ThemeExtension<DuetPalette>? other, double t) {
    if (other is! DuetPalette) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    LinearGradient g(LinearGradient a, LinearGradient b) => LinearGradient.lerp(a, b, t)!;
    return DuetPalette(
      mode: t < 0.5 ? mode : other.mode,
      accent: c(accent, other.accent),
      accent2: c(accent2, other.accent2),
      quote: c(quote, other.quote),
      background: c(background, other.background),
      surface: c(surface, other.surface),
      surfaceHigh: c(surfaceHigh, other.surfaceHigh),
      outline: c(outline, other.outline),
      accentGradient: g(accentGradient, other.accentGradient),
      movieGradient: g(movieGradient, other.movieGradient),
      musicGradient: g(musicGradient, other.musicGradient),
      youtubeGradient: g(youtubeGradient, other.youtubeGradient),
      backgroundGradient: g(backgroundGradient, other.backgroundGradient),
    );
  }
}

extension DuetThemeContext on BuildContext {
  /// Mode-dependent colours and gradients.
  DuetPalette get palette => Theme.of(this).extension<DuetPalette>() ?? DuetPalette.general;

  /// Mode-dependent wording, taps, reactions…
  ModeCopy get copy => palette.copy;
}

ThemeData buildDuetTheme(DuetPalette p) {
  final scheme = ColorScheme.fromSeed(
    seedColor: p.accent2,
    brightness: Brightness.dark,
  ).copyWith(
    primary: p.accent,
    onPrimary: Colors.white,
    secondary: p.accent2,
    onSecondary: Colors.white,
    surface: p.surface,
    onSurface: DuetColors.text,
    error: DuetColors.danger,
    outline: p.outline,
  );

  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: p.background,
  );

  final text = base.textTheme.apply(
    bodyColor: DuetColors.text,
    displayColor: DuetColors.text,
  );

  return base.copyWith(
    extensions: [p],
    textTheme: text.copyWith(
      headlineMedium: text.headlineMedium?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.5),
      headlineSmall: text.headlineSmall?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.3),
      titleLarge: text.titleLarge?.copyWith(fontWeight: FontWeight.w700),
      titleMedium: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      foregroundColor: DuetColors.text,
    ),
    cardTheme: CardThemeData(
      color: p.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: p.outline, width: 0.6),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: p.surfaceHigh,
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      hintStyle: const TextStyle(color: DuetColors.textFaint),
      labelStyle: const TextStyle(color: DuetColors.textMuted),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: p.accent, width: 1.4),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: DuetColors.danger, width: 1.2),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: p.accent,
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(54),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: DuetColors.text,
        minimumSize: const Size.fromHeight(50),
        side: BorderSide(color: p.outline),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: p.accent),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: p.surfaceHigh,
      contentTextStyle: const TextStyle(color: DuetColors.text, fontWeight: FontWeight.w500),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: p.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: p.surface,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: p.accent,
      inactiveTrackColor: const Color(0x33FFFFFF),
      thumbColor: Colors.white,
      overlayColor: p.accent.withValues(alpha: 0.2),
      trackHeight: 3,
    ),
    dividerTheme: DividerThemeData(color: p.outline, thickness: 0.6),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: p.accent),
  );
}
