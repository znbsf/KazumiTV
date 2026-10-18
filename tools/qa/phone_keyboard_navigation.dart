// Debug-only emulator fixture. Never imported by production main.dart.
import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
// ignore: depend_on_referenced_packages
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/bean/widget/phone_keyboard_control.dart';
import 'package:kazumi/bean/widget/tv_app_shell.dart';
import 'package:kazumi/bean/widget/tv_text_entry.dart';
import 'package:kazumi/navigation.dart';
import 'package:kazumi/services/phone_keyboard.dart';
import 'package:kazumi/services/platform/tv_mode.dart';
import 'package:kazumi/services/storage/storage.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kDebugMode ||
      (await PackageInfo.fromPlatform()).packageName !=
          'com.znbsf.kazumi.fluttertv.featureqa') {
    throw StateError('Requires isolated featureqa debug identity');
  }
  await TvMode.initialize();
  if (!TvMode.enabled) throw StateError('Requires TV flavor');
  final root = await getApplicationSupportDirectory();
  await Hive.initFlutter('${root.path}/qa-phone-keyboard/hive');
  await GStorage.init();
  FocusManager.instance.highlightStrategy =
      FocusHighlightStrategy.alwaysTraditional;
  runApp(MaterialApp(
    navigatorKey: rootNavigatorKey,
    scaffoldMessengerKey: rootScaffoldMessengerKey,
    navigatorObservers: [KazumiDialog.observer, rootRouteObserver],
    theme: ThemeData.dark(useMaterial3: true),
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    supportedLocales: const [Locale('zh', 'CN')],
    locale: const Locale('zh', 'CN'),
    builder: (_, child) => TvAppShell(child: child!),
    home: const _PhoneKeyboardQa(),
  ));
}

class _PhoneKeyboardQa extends StatefulWidget {
  const _PhoneKeyboardQa();
  @override
  State<_PhoneKeyboardQa> createState() => _PhoneKeyboardQaState();
}

class _PhoneKeyboardQaState extends State<_PhoneKeyboardQa> {
  final _controllers = List.generate(3, (_) => TextEditingController());
  final _focus = List.generate(3, (i) => FocusNode(debugLabel: 'phone-qa-$i'));
  final _executions = [0, 0, 0];
  final _submissions = [0, 0, 0];
  static const _ids = ['search', 'rule-url', 'sensitive'];
  static const _labels = ['搜索关键词', '规则 URL', '敏感字段（禁用手机输入）'];

  @override
  void initState() {
    super.initState();
    for (var i = 0; i < _focus.length; i++) {
      _focus[i].addListener(() {
        if (_focus[i].hasFocus) _log(i);
      });
    }
  }

  void _log(int index) => debugPrint(
      'NAV_QA fieldid=${_ids[index]} length=${_controllers[index].text.runes.length}');

  @override
  void dispose() {
    unawaited(PhoneKeyboard.instance.disconnect());
    for (final controller in _controllers) {
      controller.dispose();
    }
    for (final focus in _focus) {
      focus.dispose();
    }
    super.dispose();
  }

  Widget _field(int index) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(children: [
          Expanded(
              child: TvTextEntry(
            title: _labels[index],
            allowPhoneKeyboard: index != 2,
            child: TextField(
              controller: _controllers[index],
              focusNode: _focus[index],
              decoration: InputDecoration(labelText: _labels[index]),
              onChanged: (_) {
                _log(index);
                setState(() {});
              },
              onSubmitted: (_) {
                _log(index);
                setState(() => _submissions[index]++);
              },
            ),
          )),
          const SizedBox(width: 16),
          FilledButton(
              onPressed: () {
                _log(index);
                setState(() => _executions[index]++);
              },
              child: Text('电视执行 ${_executions[index]}')),
          const SizedBox(width: 12),
          Text('提交回调 ${_submissions[index]}'),
        ]),
      );

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('手机键盘模拟器验收')),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('手机确认只更新草稿；电视执行按钮仅增加计数，不发起搜索或安装。'),
            const SizedBox(height: 12),
            ListenableBuilder(
                listenable: PhoneKeyboard.instance,
                builder: (context, _) {
                  final keyboard = PhoneKeyboard.instance;
                  return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(children: [
                          FilledButton(
                              autofocus: true,
                              onPressed: keyboard.starting ||
                                      keyboard.uri != null
                                  ? null
                                  : () => keyboard.start(
                                      address: InternetAddress.loopbackIPv4),
                              child: const Text('开启本机模拟器键盘')),
                          const SizedBox(width: 16),
                          const PhoneKeyboardButton(),
                        ]),
                        const SizedBox(height: 8),
                        SelectableText(keyboard.uri?.toString() ??
                            keyboard.error ??
                            '尚未开启临时会话'),
                      ]);
                }),
            const SizedBox(height: 20),
            for (var i = 0; i < _controllers.length; i++) _field(i),
          ]),
        ),
      );
}
