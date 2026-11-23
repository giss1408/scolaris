import 'package:flutter/material.dart';

abstract final class Space {
  static const xs = 4.0, sm = 8.0, md = 16.0, lg = 24.0, xl = 32.0, xxl = 48.0;
}

abstract final class Radii {
  static const sm = 8.0, md = 12.0, pill = 999.0;
}

/// Palette. One accent (deep teal, white text 5.5:1); semantic colours only for status.
abstract final class Palette {
  static const accent = Color(0xFF0F766E);
  static const ink = Color(0xFF0F172A);
  static const body = Color(0xFF475569);
  static const line = Color(0xFFE2E8F0);
  static const page = Color(0xFFF8FAFC);
  static const surface = Color(0xFFFFFFFF);
  static const success = Color(0xFF15803D);
  static const warning = Color(0xFFB45309);
  static const danger = Color(0xFFB91C1C);
}

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(seedColor: Palette.accent, brightness: Brightness.light).copyWith(
    primary: Palette.accent,
    onPrimary: Colors.white,
    error: Palette.danger,
    surface: Palette.surface,
    onSurface: Palette.ink,
    outline: Palette.line,
    outlineVariant: Palette.line,
  );
  final base = ThemeData(useMaterial3: true, colorScheme: scheme);
  final text = base.textTheme
      .apply(bodyColor: Palette.ink, displayColor: Palette.ink)
      .copyWith(
        labelSmall: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.6, color: Palette.body),
        labelMedium: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Palette.body),
        bodySmall: const TextStyle(fontSize: 12, height: 1.4, color: Palette.body),
        bodyMedium: const TextStyle(fontSize: 14, height: 1.5, color: Palette.ink),
        bodyLarge: const TextStyle(fontSize: 16, height: 1.5, color: Palette.ink),
        titleSmall: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Palette.ink),
        titleMedium: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Palette.ink),
        titleLarge: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: Palette.ink),
        headlineSmall: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: Palette.ink),
        headlineMedium: const TextStyle(fontSize: 30, fontWeight: FontWeight.w700, color: Palette.ink),
      );
  final border = OutlineInputBorder(borderRadius: BorderRadius.circular(Radii.md), borderSide: const BorderSide(color: Palette.line));
  return base.copyWith(
    scaffoldBackgroundColor: Palette.page,
    textTheme: text,
    appBarTheme: const AppBarTheme(backgroundColor: Palette.page, foregroundColor: Palette.ink, elevation: 0, scrolledUnderElevation: 0, centerTitle: false),
    cardTheme: CardTheme(
      color: Palette.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.md), side: const BorderSide(color: Palette.line)),
    ),
    dividerTheme: const DividerThemeData(color: Palette.line, space: 1, thickness: 1),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Palette.surface,
      border: border,
      enabledBorder: border,
      focusedBorder: border.copyWith(borderSide: const BorderSide(color: Palette.accent, width: 2)),
      errorBorder: border.copyWith(borderSide: const BorderSide(color: Palette.danger)),
      focusedErrorBorder: border.copyWith(borderSide: const BorderSide(color: Palette.danger, width: 2)),
      contentPadding: const EdgeInsets.symmetric(horizontal: Space.md, vertical: 14),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.md)), textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52), side: const BorderSide(color: Palette.line), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.md)), textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Palette.surface,
      indicatorColor: Palette.accent.withOpacity(0.12),
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      labelTextStyle: WidgetStateProperty.resolveWith((s) => TextStyle(fontSize: 12, fontWeight: s.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500, color: s.contains(WidgetState.selected) ? Palette.accent : Palette.body)),
    ),
    chipTheme: base.chipTheme.copyWith(side: const BorderSide(color: Palette.line), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.pill))),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    bottomSheetTheme: const BottomSheetThemeData(backgroundColor: Palette.surface, showDragHandle: true),
  );
}
