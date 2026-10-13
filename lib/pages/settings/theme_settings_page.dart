import 'package:kazumi/bean/widget/tv_settings_menu_anchor.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/bean/card/palette_card.dart';
import 'package:kazumi/utils/constants.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/bean/settings/theme_provider.dart';
import 'package:kazumi/bean/settings/color_type.dart';
import 'package:kazumi/bean/settings/settings_detail_scaffold.dart';
import 'package:kazumi/bean/settings/settings_list.dart';
import 'package:window_manager/window_manager.dart';
import 'package:kazumi/utils/device.dart';
import 'package:kazumi/utils/theme.dart';

class ThemeSettingsPage extends StatefulWidget {
  const ThemeSettingsPage({super.key});

  @override
  State<ThemeSettingsPage> createState() => _ThemeSettingsPageState();
}

class _ThemeSettingsPageState extends State<ThemeSettingsPage> {
  late dynamic defaultThemeMode;
  late dynamic defaultThemeColor;
  late bool oledEnhance;
  late bool useDynamicColor;
  late bool showWindowButton;
  late bool useSystemFont;
  late final ThemeProvider themeProvider;
  final MenuController menuController = MenuController();

  @override
  void initState() {
    super.initState();
    defaultThemeMode = GStorage.getSetting(SettingsKeys.themeMode);
    defaultThemeColor = GStorage.getSetting(SettingsKeys.themeColor);
    oledEnhance = GStorage.getSetting(SettingsKeys.oledEnhance);
    useDynamicColor = GStorage.getSetting(SettingsKeys.useDynamicColor);
    showWindowButton = GStorage.getSetting(SettingsKeys.showWindowButton);
    useSystemFont = GStorage.getSetting(SettingsKeys.useSystemFont);
    themeProvider = context.read<ThemeProvider>();
  }

  Future<void> setTheme(Color? color, {bool persistSelection = true}) async {
    var defaultDarkTheme = ThemeData(
        useMaterial3: true,
        fontFamily: themeProvider.currentFontFamily,
        brightness: Brightness.dark,
        colorSchemeSeed: color,
        progressIndicatorTheme: progressIndicatorTheme2024,
        sliderTheme: sliderTheme2024,
        pageTransitionsTheme: pageTransitionsTheme2024);
    var oledTheme = oledDarkTheme(defaultDarkTheme);
    themeProvider.setTheme(
      ThemeData(
          useMaterial3: true,
          fontFamily: themeProvider.currentFontFamily,
          brightness: Brightness.light,
          colorSchemeSeed: color,
          progressIndicatorTheme: progressIndicatorTheme2024,
          sliderTheme: sliderTheme2024,
          pageTransitionsTheme: pageTransitionsTheme2024),
      oledEnhance ? oledTheme : defaultDarkTheme,
    );
    if (persistSelection) {
      defaultThemeColor = color?.toARGB32().toRadixString(16) ?? 'default';
      await GStorage.putSetting(SettingsKeys.themeColor, defaultThemeColor);
    }
  }

  Future<void> resetTheme() async {
    var defaultDarkTheme = ThemeData(
        useMaterial3: true,
        fontFamily: themeProvider.currentFontFamily,
        brightness: Brightness.dark,
        colorSchemeSeed: Colors.green,
        progressIndicatorTheme: progressIndicatorTheme2024,
        sliderTheme: sliderTheme2024,
        pageTransitionsTheme: pageTransitionsTheme2024);
    var oledTheme = oledDarkTheme(defaultDarkTheme);
    themeProvider.setTheme(
      ThemeData(
          useMaterial3: true,
          fontFamily: themeProvider.currentFontFamily,
          brightness: Brightness.light,
          colorSchemeSeed: Colors.green,
          progressIndicatorTheme: progressIndicatorTheme2024,
          sliderTheme: sliderTheme2024,
          pageTransitionsTheme: pageTransitionsTheme2024),
      oledEnhance ? oledTheme : defaultDarkTheme,
    );
    defaultThemeColor = 'default';
    await GStorage.putSetting(SettingsKeys.themeColor, 'default');
  }

  void updateTheme(String theme) async {
    if (theme == 'dark') {
      themeProvider.setThemeMode(ThemeMode.dark);
    }
    if (theme == 'light') {
      themeProvider.setThemeMode(ThemeMode.light);
    }
    if (theme == 'system') {
      themeProvider.setThemeMode(ThemeMode.system);
    }
    await GStorage.putSetting(SettingsKeys.themeMode, theme);
    setState(() {
      defaultThemeMode = theme;
    });

    // Update Windows title bar theme
    if (Platform.isWindows) {
      await windowManager.setBrightness(
          themeProvider.isEffectiveDark() ? Brightness.dark : Brightness.light);
    }
  }

  void updateOledEnhance() {
    dynamic color;
    oledEnhance = GStorage.getSetting(SettingsKeys.oledEnhance);
    if (defaultThemeColor == 'default') {
      color = Colors.green;
    } else {
      color = Color(int.parse(defaultThemeColor, radix: 16));
    }
    setTheme(color, persistSelection: false);
  }

  @override
  Widget build(BuildContext context) {
    return SettingsDetailScaffold(
      title: const Text('外观设置'),
      body: SettingsList(
        sections: [
          SettingsSection(
            title: Text('外观'),
            tiles: [
              SettingsTile(
                leading: Icons.dark_mode_rounded,
                onPressed: (_) {
                  if (menuController.isOpen) {
                    menuController.close();
                  } else {
                    menuController.open();
                  }
                },
                title: Text('深色模式'),
                value: TvSettingsMenuAnchor(
                  consumeOutsideTap: true,
                  controller: menuController,
                  builder: (_, __, ___) {
                    return Text(
                      defaultThemeMode == 'light'
                          ? '浅色'
                          : (defaultThemeMode == 'dark' ? '深色' : '跟随系统'),
                    );
                  },
                  menuChildren: [
                    MenuItemButton(
                      requestFocusOnHover: false,
                      onPressed: () => updateTheme('system'),
                      child: Container(
                        height: 48,
                        constraints: BoxConstraints(minWidth: 112),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Row(
                            children: [
                              Icon(
                                Icons.brightness_auto_rounded,
                                color: defaultThemeMode == 'system'
                                    ? Theme.of(context).colorScheme.primary
                                    : null,
                              ),
                              SizedBox(width: 8),
                              Text(
                                '跟随系统',
                                style: TextStyle(
                                  color: defaultThemeMode == 'system'
                                      ? Theme.of(context).colorScheme.primary
                                      : null,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    MenuItemButton(
                      requestFocusOnHover: false,
                      onPressed: () => updateTheme('light'),
                      child: Container(
                        height: 48,
                        constraints: BoxConstraints(minWidth: 112),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Row(
                            children: [
                              Icon(
                                Icons.light_mode_rounded,
                                color: defaultThemeMode == 'light'
                                    ? Theme.of(context).colorScheme.primary
                                    : null,
                              ),
                              SizedBox(width: 8),
                              Text(
                                '浅色',
                                style: TextStyle(
                                    color: defaultThemeMode == 'light'
                                        ? Theme.of(context).colorScheme.primary
                                        : null),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    MenuItemButton(
                      requestFocusOnHover: false,
                      onPressed: () => updateTheme('dark'),
                      child: Container(
                        height: 48,
                        constraints: BoxConstraints(minWidth: 112),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Row(
                            children: [
                              Icon(
                                Icons.dark_mode_rounded,
                                color: defaultThemeMode == 'dark'
                                    ? Theme.of(context).colorScheme.primary
                                    : null,
                              ),
                              SizedBox(width: 8),
                              Text(
                                '深色',
                                style: TextStyle(
                                  color: defaultThemeMode == 'dark'
                                      ? Theme.of(context).colorScheme.primary
                                      : null,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              SettingsTile(
                leading: Icons.palette_rounded,
                enabled: !useDynamicColor,
                onPressed: (_) async {
                  final selected = await showDialog<int>(
                      context: context,
                      builder: (_) =>
                          ThemePaletteDialog(selectedColor: defaultThemeColor));
                  if (!mounted || selected == null) return;
                  if (selected == 0) {
                    await resetTheme();
                  } else {
                    await setTheme(colorThemeTypes[selected]['color']);
                  }
                  if (mounted) setState(() {});
                },
                title: const Text('配色方案'),
              ),
              SettingsTile.switchTile(
                leading: Icons.colorize_rounded,
                enabled: !Platform.isIOS,
                onToggle: (value) async {
                  useDynamicColor = value ?? !useDynamicColor;
                  await GStorage.putSetting(
                      SettingsKeys.useDynamicColor, useDynamicColor);
                  themeProvider.setDynamic(useDynamicColor);
                  setState(() {});
                },
                title: Text('动态配色'),
                initialValue: useDynamicColor,
              ),
              SettingsTile.switchTile(
                leading: Icons.font_download_rounded,
                onToggle: (value) async {
                  useSystemFont = value ?? !useSystemFont;
                  await GStorage.putSetting(
                      SettingsKeys.useSystemFont, useSystemFont);
                  themeProvider.setFontFamily(useSystemFont);
                  dynamic color;
                  if (defaultThemeColor == 'default') {
                    color = Colors.green;
                  } else {
                    color = Color(int.parse(defaultThemeColor, radix: 16));
                  }
                  setTheme(color, persistSelection: false);
                  setState(() {});
                },
                title: Text('使用系统字体'),
                description: Text('关闭后使用 MI Sans 字体'),
                initialValue: useSystemFont,
              ),
            ],
            bottomInfo: Text('动态配色仅支持安卓12及以上和桌面平台'),
          ),
          SettingsSection(
            title: Text('显示'),
            tiles: [
              SettingsTile.switchTile(
                leading: Icons.contrast_rounded,
                onToggle: (value) async {
                  oledEnhance = value ?? !oledEnhance;
                  await GStorage.putSetting(
                      SettingsKeys.oledEnhance, oledEnhance);
                  updateOledEnhance();
                  setState(() {});
                },
                title: Text('OLED优化'),
                description: Text('深色模式下使用纯黑背景'),
                initialValue: oledEnhance,
              ),
            ],
          ),
          if (isDesktop())
            SettingsSection(
              title: Text('窗口'),
              tiles: [
                SettingsTile.switchTile(
                  leading: Icons.web_asset_rounded,
                  onToggle: (value) async {
                    showWindowButton = value ?? !showWindowButton;
                    await GStorage.putSetting(
                        SettingsKeys.showWindowButton, showWindowButton);
                    setState(() {});
                  },
                  title: Text('使用系统标题栏'),
                  description: Text('重启应用生效'),
                  initialValue: showWindowButton,
                ),
              ],
            ),
          if (Platform.isAndroid)
            SettingsSection(
              title: Text('屏幕'),
              tiles: [
                SettingsTile(
                  leading: Icons.sixty_fps_rounded,
                  onPressed: (_) async {
                    context.pushNamed('/settings/theme/display');
                  },
                  title: Text('屏幕帧率'),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// A native focusable button gives every swatch the same remote/touch action.
/// Cancel returns null; the page persists only an explicitly selected color.
class ThemePaletteDialog extends StatelessWidget {
  const ThemePaletteDialog({super.key, required this.selectedColor});
  final String selectedColor;
  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('配色方案'),
        content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
                child: Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                  for (var index = 0; index < colorThemeTypes.length; index++)
                    OutlinedButton(
                      key: ValueKey('theme-palette-$index'),
                      autofocus: selectedColor == 'default'
                          ? index == 0
                          : (colorThemeTypes[index]['color'] as Color)
                                  .toARGB32()
                                  .toRadixString(16) ==
                              selectedColor,
                      onPressed: () => Navigator.of(context).pop(index),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        PaletteCard(
                            color: colorThemeTypes[index]['color'],
                            selected: selectedColor == 'default'
                                ? index == 0
                                : (colorThemeTypes[index]['color'] as Color)
                                        .toARGB32()
                                        .toRadixString(16) ==
                                    selectedColor),
                        Text(colorThemeTypes[index]['label']),
                      ]),
                    ),
                ]))),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'))
        ],
      );
}
