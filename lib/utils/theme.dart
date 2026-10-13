import 'package:flutter/material.dart';

ThemeData oledDarkTheme(ThemeData defaultDarkTheme) {
  if (defaultDarkTheme.brightness != Brightness.dark) return defaultDarkTheme;
  return defaultDarkTheme.copyWith(
    scaffoldBackgroundColor: Colors.black,
    colorScheme: defaultDarkTheme.colorScheme.copyWith(
      onPrimary: Colors.black,
      onSecondary: Colors.black,
      surface: Colors.black,
      onSurface: Colors.white,
    ),
  );
}
