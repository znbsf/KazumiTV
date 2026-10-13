import 'package:kazumi/bean/widget/tv_player_side_panel.dart';
import 'package:kazumi/pages/player/tv_player_controls.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kazumi/pages/settings/theme_settings_page.dart';
import 'package:kazumi/bean/settings/theme_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/bean/widget/tv_visuals.dart';
import 'package:kazumi/utils/theme.dart';

void main() {
  for (final brightness in Brightness.values) {
    test('TV shell preserves user $brightness palette', () {
      final original = ThemeData(
          colorScheme: ColorScheme.fromSeed(
              seedColor: Colors.pink, brightness: brightness));
      final tv = TvVisuals.theme(original);
      expect(tv.brightness, brightness);
      expect(tv.colorScheme, original.colorScheme);
    });
  }
  test('OLED does not blacken a light theme', () {
    final light = ThemeData.light();
    final tv = TvVisuals.theme(light, oled: true);
    expect(tv.brightness, Brightness.light);
    expect(tv.scaffoldBackgroundColor, light.scaffoldBackgroundColor);
  });
  test(
      'OLED dark main surfaces are exactly opaque black, containers stay legible',
      () {
    final dark = ThemeData.dark();
    final oled = oledDarkTheme(dark);
    final tv = TvVisuals.theme(oled, oled: true);
    expect(tv.scaffoldBackgroundColor, const Color(0xff000000));
    expect(tv.colorScheme.surface, const Color(0xff000000));
    expect(tv.colorScheme.surfaceContainer, dark.colorScheme.surfaceContainer);
  });
  for (final brightness in Brightness.values) {
    testWidgets('player panel and focused action follow $brightness palette',
        (tester) async {
      final theme =
          ThemeData(colorSchemeSeed: Colors.pink, brightness: brightness);
      await tester.pumpWidget(MaterialApp(
          theme: theme,
          home: Scaffold(
            body: TvPlayerSidePanel(
                opacity: 1,
                child: TvPlayerAction(
                  label: 'Play',
                  autofocus: true,
                  onPressed: () {},
                )),
          )));
      await tester.pumpAndSettle();
      final panel = find.descendant(
          of: find.byType(TvPlayerSidePanel),
          matching: find.byType(ColoredBox));
      expect(tester.widget<ColoredBox>(panel).color, theme.colorScheme.surface);
      expect(tester.widget<Text>(find.text('Play')).style?.color,
          theme.colorScheme.primary);
      // Controls carry their own themed surface so light text colors do not
      // disappear into the black video gradient behind them.
      final material = find.descendant(
          of: find.byType(TvPlayerAction), matching: find.byType(Material));
      expect(tester.widget<Material>(material).color,
          theme.colorScheme.surface.withValues(alpha: .94));
    });
  }
  testWidgets(
      'palette OK commits focused swatch; cancel leaves selection untouched',
      (tester) async {
    int? selected;
    var commits = 0;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Builder(
                builder: (context) => TextButton(
                    onPressed: () async {
                      final result = await showDialog<int>(
                          context: context,
                          builder: (_) => const ThemePaletteDialog(
                              selectedColor: 'default'));
                      if (result != null) {
                        selected = result;
                        commits++;
                      }
                    },
                    child: const Text('Open'))))));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(selected, 1);
    expect(commits, 1);
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(commits, 1);
    expect(selected, 1);
  });
  testWidgets('already open palette follows root theme change', (tester) async {
    final theme = ValueNotifier(ThemeData(colorSchemeSeed: Colors.green));
    await tester.pumpWidget(ValueListenableBuilder<ThemeData>(
        valueListenable: theme,
        builder: (_, value, __) => MaterialApp(
            theme: value,
            home: Scaffold(
                body: Builder(
                    builder: (context) => TextButton(
                        onPressed: () => showDialog<void>(
                            context: context,
                            builder: (_) => const ThemePaletteDialog(
                                selectedColor: 'default')),
                        child: const Text('Open')))))));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    theme.value =
        ThemeData(colorSchemeSeed: Colors.pink, brightness: Brightness.dark);
    await tester.pumpAndSettle();
    final context = tester.element(find.byType(ThemePaletteDialog));
    expect(
        Theme.of(context).colorScheme.primary, theme.value.colorScheme.primary);
    expect(Theme.of(context).brightness, Brightness.dark);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    theme.dispose();
  });
  testWidgets(
      'follow-system brightness tracks platform without overwriting choice',
      (tester) async {
    final provider = ThemeProvider();
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    expect(provider.isEffectiveDark(), isTrue);
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    expect(provider.isEffectiveDark(), isFalse);
    provider.setThemeMode(ThemeMode.dark);
    expect(provider.isEffectiveDark(), isTrue);
    expect(provider.themeMode, ThemeMode.dark);
    tester.platformDispatcher.clearPlatformBrightnessTestValue();
    provider.dispose();
  });
}
