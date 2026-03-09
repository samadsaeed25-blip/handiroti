import 'package:flutter/material.dart';

ThemeData buildHandiTheme() {
  const bg = Color(0xFFF6F7FB);
  const surface = Colors.white;
  const text = Color(0xFF0B1220);
  const muted = Color(0xFF667085);
  const border = Color(0xFFE6E8EF);

  final base = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xFF111827),
      brightness: Brightness.light,
      surface: surface,
      background: bg,
    ),
    scaffoldBackgroundColor: bg,
    dividerColor: border,
    textTheme: const TextTheme(
      headlineSmall: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: text),
      titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: text),
      bodyLarge: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: text),
      bodyMedium: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: text),
      bodySmall: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: muted),
      labelLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
    ),
  );

  return base.copyWith(
    appBarTheme: const AppBarTheme(
      elevation: 0,
      centerTitle: false,
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      foregroundColor: text,
      titleTextStyle: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: text),
    ),
    cardTheme: CardThemeData(
  color: surface,
  elevation: 0,
  shape: RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(18),
    side: const BorderSide(color: border),
  ),
),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFB6BBCB)),
      ),
      hintStyle: const TextStyle(color: Color(0xFF98A2B3), fontWeight: FontWeight.w500),
    ),
    chipTheme: base.chipTheme.copyWith(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      side: const BorderSide(color: border),
      labelStyle: const TextStyle(fontWeight: FontWeight.w700),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: const Color(0xFFD6A21A),
        foregroundColor: const Color(0xFF1B1B1B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        textStyle: const TextStyle(fontWeight: FontWeight.w900),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFFD6A21A),
        foregroundColor: const Color(0xFF1B1B1B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        textStyle: const TextStyle(fontWeight: FontWeight.w900),
        elevation: 0,
      ),
    ),
  );
}
