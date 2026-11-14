import 'package:flutter/material.dart';

/// Central visual tokens so screens do not hardcode colours.
class SkinStandTheme {
  const SkinStandTheme._();

  static const Color background = Color(0xFF101010);
  static const Color surface = Color(0xFF1B1B1B);
  static const Color surfaceHigh = Color(0xFF262626);
  static const Color border = Color(0xFF333333);
  static const Color accent = Color(0xFFFF8A00);
  static const Color accentSoft = Color(0xFFFFB74D);
  static const Color success = Color(0xFF2E7D32);
  static const Color danger = Color(0xFFC62828);

  static ThemeData build() {
    final ColorScheme scheme = ColorScheme.fromSeed(
      seedColor: accent,
      brightness: Brightness.dark,
    ).copyWith(
      primary: accent,
      secondary: accentSoft,
      surface: surface,
      onSurface: Colors.white,
      error: danger,
    );

    final ThemeData base = ThemeData(useMaterial3: true, colorScheme: scheme);

    return base.copyWith(
      scaffoldBackgroundColor: background,
      appBarTheme: const AppBarTheme(
        backgroundColor: surface,
        foregroundColor: accent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          color: accent,
          fontSize: 18,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
        ),
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size.fromHeight(50),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(fontWeight: FontWeight.w700, letterSpacing: 0.6),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(46),
          foregroundColor: Colors.white,
          side: const BorderSide(color: border),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceHigh,
        hintStyle: const TextStyle(color: Colors.white38),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
      dividerTheme: const DividerThemeData(color: border, space: 1),
      listTileTheme: const ListTileThemeData(iconColor: accentSoft),
    );
  }
}
