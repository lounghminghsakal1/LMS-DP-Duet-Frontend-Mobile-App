import 'package:flutter/material.dart';

/// Duet's palette: a cosy "movie night" dark theme with a pink → violet accent.
abstract final class DuetColors {
  static const background = Color(0xFF0E0A1C);
  static const surface = Color(0xFF19132E);
  static const surfaceHigh = Color(0xFF241C40);
  static const outline = Color(0xFF3A2F5F);
  static const pink = Color(0xFFFF5E8A);
  static const violet = Color(0xFF8B5CF6);
  static const peach = Color(0xFFFFB37A);
  static const mint = Color(0xFF4ADE9B);
  static const amber = Color(0xFFFFC857);
  static const danger = Color(0xFFFF6B6B);
  static const text = Color(0xFFF5F1FF);
  static const textMuted = Color(0xFFB3A9D6);
  static const textFaint = Color(0xFF7D73A3);

  static const accentGradient = LinearGradient(
    colors: [pink, violet],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const movieGradient = LinearGradient(
    colors: [Color(0xFFFF5E8A), Color(0xFFB0447A)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const musicGradient = LinearGradient(
    colors: [Color(0xFF8B5CF6), Color(0xFF4F46E5)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const youtubeGradient = LinearGradient(
    colors: [Color(0xFFFF7A59), Color(0xFFE11D48)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const backgroundGradient = LinearGradient(
    colors: [Color(0xFF1A1033), background, Color(0xFF0A0716)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    stops: [0, 0.45, 1],
  );
}

ThemeData buildDuetTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: DuetColors.violet,
    brightness: Brightness.dark,
  ).copyWith(
    primary: DuetColors.pink,
    onPrimary: Colors.white,
    secondary: DuetColors.violet,
    onSecondary: Colors.white,
    surface: DuetColors.surface,
    onSurface: DuetColors.text,
    error: DuetColors.danger,
    outline: DuetColors.outline,
  );

  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: DuetColors.background,
  );

  final text = base.textTheme.apply(
    bodyColor: DuetColors.text,
    displayColor: DuetColors.text,
  );

  return base.copyWith(
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
      color: DuetColors.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: DuetColors.outline, width: 0.6),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: DuetColors.surfaceHigh,
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      hintStyle: const TextStyle(color: DuetColors.textFaint),
      labelStyle: const TextStyle(color: DuetColors.textMuted),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: DuetColors.pink, width: 1.4),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: DuetColors.danger, width: 1.2),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: DuetColors.pink,
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
        side: const BorderSide(color: DuetColors.outline),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: DuetColors.pink),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: DuetColors.surfaceHigh,
      contentTextStyle: const TextStyle(color: DuetColors.text, fontWeight: FontWeight.w500),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: DuetColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: DuetColors.surface,
      showDragHandle: true,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    ),
    sliderTheme: const SliderThemeData(
      activeTrackColor: DuetColors.pink,
      inactiveTrackColor: Color(0x33FFFFFF),
      thumbColor: Colors.white,
      overlayColor: Color(0x33FF5E8A),
      trackHeight: 3,
    ),
    dividerTheme: const DividerThemeData(color: DuetColors.outline, thickness: 0.6),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: DuetColors.pink),
  );
}
