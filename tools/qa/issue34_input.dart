// Isolated device fixture; never imported by production main.dart.
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:hive_ce/hive.dart';
// ignore: depend_on_referenced_packages
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/bean/widget/phone_keyboard_control.dart';
import 'package:kazumi/bean/widget/tv_app_shell.dart';
import 'package:kazumi/navigation.dart';
import 'package:kazumi/pages/info/source_keyword_dialog.dart';
import 'package:kazumi/pages/settings/sync/bangumi_sync_page.dart';
import 'package:kazumi/pages/settings/sync/webdav_server_page.dart';
import 'package:kazumi/bean/widget/tv_text_prompt_dialog.dart';
import 'package:kazumi/pages/video/episode_jump_dialog.dart';
import 'package:kazumi/pages/plugin_editor/editor_form_widgets.dart';
import 'package:kazumi/services/phone_keyboard.dart';
import 'package:kazumi/services/platform/tv_mode.dart';
import 'package:kazumi/services/storage/storage.dart';

class _Paths extends PathProviderPlatform {
  _Paths(this.root);
  final String root;
  @override
  Future<String?> getApplicationSupportPath() async => root;
  @override
  Future<String?> getApplicationDocumentsPath() async => root;
  @override
  Future<String?> getTemporaryPath() async => root;
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if ((await PackageInfo.fromPlatform()).packageName !=
      'com.znbsf.kazumi.fluttertv.remoteqa') {
    throw StateError('Requires remoteqa identity');
  }
  await TvMode.initialize();
  if (!TvMode.enabled) throw StateError('Requires TV mode');
  final root =
      '${(await getApplicationSupportDirectory()).path}/issue34-20261028';
  await Directory('$root/hive').create(recursive: true);
  // Redirect both Hive and GStorage recovery/backup paths away from real QA data.
  PathProviderPlatform.instance = _Paths(root);
  Hive.init('$root/hive');
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
    home: const _InputQa(),
  ));
}

class _InputQa extends StatefulWidget {
  const _InputQa();
  @override
  State<_InputQa> createState() => _InputQaState();
}

class _InputQaState extends State<_InputQa> {
  final rule = TextEditingController();
  String actionResult = '未执行';
  @override
  void dispose() {
    rule.dispose();
    super.dispose();
  }

  Future<void> prompt(String title) async {
    final result = await showDialog<String>(
        context: context,
        builder: (_) => TvTextPromptDialog(
            title: title,
            initialText: '原始草稿',
            hint: '输入内容',
            submitLabel: '执行'));
    if (mounted) setState(() => actionResult = '$title：${result ?? '取消'}');
  }

  final words = ['来源A原词', '来源B原词'];
  final counts = [0, 0];
  void edit(int index) {
    KazumiDialog.show(
        builder: (dialogContext) => SourceKeywordDialog(
              initialKeyword: words[index],
              sourceName: index == 0 ? '测试来源A' : '测试来源B',
              onCancel: () => KazumiDialog.dismiss(context: dialogContext),
              onSubmit: (value) {
                KazumiDialog.dismiss(context: dialogContext);
                if (mounted)
                  setState(() {
                    words[index] = value;
                    counts[index]++;
                  });
              },
            ));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Issue34 输入隔离验收')),
        body: Padding(
            padding: const EdgeInsets.all(24),
            child: ListView(
              children: [
                const Text('生产输入组件；检索仅计数；Token 仅用假值，不点验证保存。'),
                const PhoneKeyboardButton(),
                for (var i = 0; i < 2; i++) ...[
                  Text('来源${i == 0 ? 'A' : 'B'}：${words[i]}；检索次数 ${counts[i]}'),
                  FilledButton(
                      onPressed: () => edit(i),
                      child: Text('编辑来源${i == 0 ? 'A' : 'B'}')),
                ],
                FilledButton(
                    onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                            builder: (_) => const BangumiSyncPage())),
                    child: const Text('打开生产 Bangumi 页面')),
                FilledButton(
                    onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                            builder: (_) => const WebDavServerPage())),
                    child: const Text('打开生产 WebDAV 页面')),
                FilledButton(
                    onPressed: () => prompt('弹幕检索'),
                    child: const Text('弹幕检索输入')),
                FilledButton(
                    onPressed: () => prompt('发送弹幕'),
                    child: const Text('弹幕发送输入')),
                FilledButton(
                    onPressed: () async {
                      final index =
                          await showEpisodeJumpDialog(context, count: 20);
                      if (mounted)
                        setState(() => actionResult =
                            '集序号：${index == null ? '取消' : index + 1}');
                    },
                    child: const Text('定位剧集输入')),
                Text(actionResult),
                EditorTextField(controller: rule, label: '规则多行输入', maxLines: 5),
                TextButton(
                    onPressed: () => PhoneKeyboard.instance.disconnect(),
                    child: const Text('断开测试遥控')),
              ],
            )),
      );
}
