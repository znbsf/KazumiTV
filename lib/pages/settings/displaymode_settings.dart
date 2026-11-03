import 'package:flutter/material.dart';
import 'package:flutter_displaymode/flutter_displaymode.dart';

import 'package:kazumi/bean/settings/settings_list.dart';
import 'package:kazumi/bean/settings/settings_detail_scaffold.dart';
import 'package:kazumi/bean/widget/loading_indicator.dart';
import 'package:kazumi/services/platform/tv_mode.dart';
import 'package:kazumi/services/storage/storage.dart';

class SetDisplayMode extends StatefulWidget {
  const SetDisplayMode({super.key});

  @override
  State<SetDisplayMode> createState() => _SetDisplayModeState();
}

class _SetDisplayModeState extends State<SetDisplayMode> {
  List<DisplayMode> modes = <DisplayMode>[];
  DisplayMode? active;
  DisplayMode? preferred;
  bool _loading = true;
  bool _failed = false;
  final _retryFocus = FocusNode(debugLabel: 'Display mode retry');

  @override
  void initState() {
    super.initState();
    init();
  }

  @override
  void dispose() {
    _retryFocus.dispose();
    super.dispose();
  }

  void _retry() {
    setState(() {
      _loading = true;
      _failed = false;
    });
    init();
  }

  Future<void> fetchAll() async {
    final currentPreferred = await FlutterDisplayMode.preferred;
    final currentActive = await FlutterDisplayMode.active;
    await GStorage.putSetting(
        SettingsKeys.displayMode, currentPreferred.toString());
    if (!mounted) return;
    setState(() {
      preferred = currentPreferred;
      active = currentActive;
    });
  }

  Future<void> init() async {
    try {
      final available = await FlutterDisplayMode.supported;
      if (available.isNotEmpty) {
        final saved = GStorage.getSetting(SettingsKeys.displayMode);
        final selected = available
                .where((mode) => mode.toString() == saved)
                .firstOrNull ??
            available.where((mode) => mode == DisplayMode.auto).firstOrNull ??
            available.first;
        await FlutterDisplayMode.setPreferredMode(selected);
        await fetchAll();
      }
      if (!mounted) return;
      setState(() {
        modes = available;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
      if (TvMode.enabled) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _failed) _retryFocus.requestFocus();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SettingsDetailScaffold(
      title: const Text('屏幕帧率设置'),
      body: _loading
          ? const LoadingIndicator()
          : _failed
              ? Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Text('无法读取屏幕帧率'),
                  TextButton(
                      focusNode: _retryFocus,
                      onPressed: _retry,
                      child: const Text('重试')),
                ]))
              : modes.isEmpty
                  ? const Center(child: Text('没有可用的屏幕帧率'))
                  : SettingsList(
                      sections: [
                        SettingsRadioSection<DisplayMode>(
                          title: Text('没有生效? 重启app试试'),
                          groupValue: preferred,
                          onChanged: (DisplayMode? newMode) async {
                            await FlutterDisplayMode.setPreferredMode(newMode!);
                            await Future<dynamic>.delayed(
                              const Duration(milliseconds: 100),
                            );
                            await fetchAll();
                          },
                          tiles: modes
                              .map((e) => SettingsTile<DisplayMode>.radioTile(
                                    radioValue: e,
                                    title: e == DisplayMode.auto
                                        ? Text('自动')
                                        : Text(
                                            '$e${e == active ? "  [系统]" : ""}'),
                                  ))
                              .toList(),
                        ),
                      ],
                    ),
    );
  }
}
