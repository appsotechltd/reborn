import 'package:flutter/material.dart';

/// Max width of reading content on wide screens.
const double kReadingWidth = 680;

const _seed = Color(0xFF4F6F64); // calm sage green

ThemeData _build(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(
    seedColor: _seed,
    brightness: brightness,
    dynamicSchemeVariant: DynamicSchemeVariant.tonalSpot,
  );
  final base = ThemeData(colorScheme: scheme, useMaterial3: true);
  final t = base.textTheme;
  final text = t.copyWith(
    headlineMedium: t.headlineMedium?.copyWith(
      fontWeight: FontWeight.w600,
      height: 1.25,
      letterSpacing: -0.2,
    ),
    headlineSmall: t.headlineSmall?.copyWith(
      fontWeight: FontWeight.w600,
      height: 1.3,
      letterSpacing: -0.1,
    ),
    titleLarge: t.titleLarge?.copyWith(
      fontWeight: FontWeight.w600,
      height: 1.3,
    ),
    bodyLarge: t.bodyLarge?.copyWith(
      fontSize: 18,
      height: 1.6,
      letterSpacing: 0.1,
    ),
    bodyMedium: t.bodyMedium?.copyWith(height: 1.5),
  );
  return base.copyWith(
    textTheme: text,
    scaffoldBackgroundColor: scheme.surface,
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
      titleTextStyle: text.titleLarge?.copyWith(color: scheme.onSurface),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      margin: EdgeInsets.zero,
    ),
    chipTheme: base.chipTheme.copyWith(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    inputDecorationTheme: const InputDecorationTheme(
      border: OutlineInputBorder(),
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}

final ThemeData lightTheme = _build(Brightness.light);
final ThemeData darkTheme = _build(Brightness.dark);
