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
    final useOled = oled && inherited.brightness == Brightness.dark;
    final scheme = useOled
        ? inherited.colorScheme.copyWith(surface: Colors.black)
        : inherited.colorScheme;
    final base = inherited.textTheme;
    return inherited.copyWith(
      colorScheme: scheme,
      scaffoldBackgroundColor: fixedSurfaces
          ? (useOled ? Colors.black : inherited.scaffoldBackgroundColor)
          : Colors.transparent,
      canvasColor: scheme.surface,
      focusColor: scheme.primary.withValues(alpha: .24),
      hoverColor: scheme.primary.withValues(alpha: .12),
      textTheme: base.copyWith(
        headlineLarge: base.headlineLarge?.merge(heading),
        headlineMedium: base.headlineMedium?.merge(heading),
        headlineSmall: base.headlineSmall?.merge(heading),
        titleLarge: base.titleLarge?.merge(title),
        titleMedium: base.titleMedium?.merge(title),
        titleSmall: base.titleSmall?.merge(control),
        bodyLarge: base.bodyLarge?.merge(body),
        bodyMedium: base.bodyMedium?.merge(body),
        bodySmall: base.bodySmall?.merge(caption),
        labelLarge: base.labelLarge?.merge(control),
        labelMedium: base.labelMedium?.merge(control),
        labelSmall: base.labelSmall?.merge(caption),
      ),
      iconTheme: IconThemeData(color: scheme.onSurface, size: 20),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      visualDensity: VisualDensity.comfortable,
    );
  }
}
