import 'package:flutter/material.dart';

/// TV visual tokens ported from native main KazumiTheme.kt (24bc50ef).
abstract final class TvVisuals {
  // A reversible diagnostic control; ordinary TV builds use the user's new
  // fixed-background, larger-card preference without preparing backdrop images.
  static const fixedSurfaces =
      bool.fromEnvironment('KAZUMI_TV_FIXED_SURFACES', defaultValue: true);
  static const accent = Color(0xFFB8E8A4);
  static const background = Color(0xFF101611);
  static const surface = Color(0xFF1C261F);
  static const selected = Color(0xFF354F38);
  static const text = Color(0xFFE8EEE5);
  static const muted = Color(0xFFB6C2B3);
  static const heading = TextStyle(
    fontSize: 23,
    height: 30 / 23,
    fontWeight: FontWeight.w500,
  );
  static const title = TextStyle(
    fontSize: 16,
    height: 22 / 16,
    fontWeight: FontWeight.w500,
  );
  static const body = TextStyle(fontSize: 15, height: 21 / 15);
  static const caption = TextStyle(fontSize: 13, height: 18 / 13);
  static const control = TextStyle(
    fontSize: 14,
    height: 20 / 14,
    fontWeight: FontWeight.w500,
  );

  static ThemeData theme(ThemeData inherited, {bool oled = false}) {
    final scheme = ColorScheme.fromSeed(
      seedColor: accent,
      brightness: Brightness.dark,
    ).copyWith(
      primary: accent,
      onPrimary: const Color(0xFF173513),
      surface: oled ? Colors.black : surface,
      surfaceContainer: surface,
      surfaceContainerHigh: surface,
      primaryContainer: selected,
      onPrimaryContainer: text,
      secondaryContainer: selected,
      onSurface: text,
      onSurfaceVariant: muted,
    );
    final base = inherited.textTheme.apply(bodyColor: text, displayColor: text);
    return inherited.copyWith(
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: fixedSurfaces
          ? (oled ? Colors.black : background)
          : Colors.transparent,
      canvasColor: surface,
      focusColor: accent.withValues(alpha: .24),
      hoverColor: accent.withValues(alpha: .12),
      textTheme: base.copyWith(
        headlineLarge: heading,
        headlineMedium: heading,
        headlineSmall: heading,
        titleLarge: title,
        titleMedium: title,
        titleSmall: control,
        bodyLarge: body,
        bodyMedium: body,
        bodySmall: caption,
        labelLarge: control,
        labelMedium: control,
        labelSmall: caption,
      ),
      iconTheme: const IconThemeData(color: text, size: 20),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: text,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      visualDensity: VisualDensity.comfortable,
    );
  }
}
