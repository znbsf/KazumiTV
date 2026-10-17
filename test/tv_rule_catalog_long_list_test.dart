import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kazumi/bean/card/rule_card.dart';
import 'package:kazumi/bean/widget/tv_focus_navigation.dart';
import 'package:kazumi/modules/plugin/plugin_http_module.dart';
import 'package:kazumi/pages/onboarding/steps/plugin_shop_step.dart';
import 'package:kazumi/pages/plugin_editor/plugin_catalog_view.dart';
import 'package:kazumi/plugins/plugins.dart';
import 'package:kazumi/plugins/plugins_controller.dart';
import 'package:kazumi/services/platform/tv_mode.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _Paths extends PathProviderPlatform {
  _Paths(this.path);
  final String path;
  @override
  Future<String?> getApplicationSupportPath() async => path;
}

String? focusedRule() {
  String? result;
  FocusManager.instance.primaryFocus?.context?.visitAncestorElements((element) {
    if (element.widget is RuleCard) {
      result = (element.widget as RuleCard).title;
      return false;
    }
    return true;
  });
  return result;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('kazumi_long_rules_');
    PathProviderPlatform.instance = _Paths(directory.path);
    Hive.init(directory.path);
    await GStorage.init();
  });
  tearDownAll(() async {
    await Hive.close();
    await directory.delete(recursive: true);
  });

  for (final onboarding in [true, false]) {
    for (final scenario in [(2, 720.0), (24, 540.0), (60, 720.0)]) {
      testWidgets(
          '${onboarding ? 'onboarding' : 'repository'} ${scenario.$1} mixed rules ${scenario.$2} high first last first and install',
          (tester) async {
        TvMode.setEnabledForTesting(true);
        addTearDown(() => TvMode.setEnabledForTesting(false));
        tester.view.physicalSize = Size(960, scenario.$2);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final names = List.generate(
            scenario.$1, (i) => 'Rule ${i.toString().padLeft(3, '0')}');
        final downloads = <String>[];
        var writes = 0;
        final controller = PluginsController(
          catalogLoader: () async => [
            for (var i = 0; i < names.length; i++)
              PluginHTTPItem(
                  name: names[i],
                  version: '1.0.0',
                  useNativePlayer: true,
                  author: 'fixture',
                  lastUpdate: names.length - i)
          ],
          pluginLoader: (name) async {
            downloads.add(name);
            return Plugin.fromTemplate()
              ..name = name
              ..version = '1.0.0'
              ..baseUrl = 'https://example.invalid';
          },
          pluginJsonWriter: (_) async {
            writes++;
          },
        );
        // A long installed region has no actionable trailing button in baseline.
        for (final name in names.skip(1).take(names.length - 2)) {
          controller.pluginList.add(Plugin.fromTemplate()
            ..name = name
            ..version = '1.0.0'
            ..baseUrl = 'https://example.invalid');
        }
        await controller.ensurePluginCatalog();
        final nav = GlobalKey<NavigatorState>();
        final returnFocus = FocusNode();
        final footerFocus = FocusNode();
        await tester.pumpWidget(MaterialApp(
            builder: (_, child) => FocusTraversalGroup(
                policy: TvLoopTraversalPolicy(), child: child!),
            navigatorKey: nav,
            home: Scaffold(
                body: TextButton(
                    focusNode: returnFocus,
                    autofocus: true,
                    onPressed: () {},
                    child: const Text('Entry')))));
        await tester.pumpAndSettle();
        expect(returnFocus.hasFocus, isTrue);
        nav.currentState!.push(MaterialPageRoute<void>(
            builder: (_) => Scaffold(
                bottomNavigationBar: Padding(
                    padding: const EdgeInsets.all(12),
                    child: TextButton(
                        focusNode: footerFocus,
                        onPressed: () {},
                        child: const Text('Continue fixture'))),
                body: onboarding
                    ? PluginShopStep(controller: controller)
                    : PluginCatalogView(controller: controller))));
        await tester.pumpAndSettle();
        final first = find.byKey(ValueKey(names.first));
        await tester.ensureVisible(first);
        await tester.pumpAndSettle();
        final button =
            find.descendant(of: first, matching: find.byType(FilledButton));
        final focus = Focus.of(tester.element(
            find.descendant(of: button, matching: find.byType(Icon)).first));
        focus.requestFocus();
        await tester.pumpAndSettle();
        expect(focusedRule(), names.first);
        for (var i = 0;
            i < names.length + 8 && focusedRule() != names.last;
            i++) {
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
          await tester.pumpAndSettle();
        }
        expect(focusedRule(), names.last,
            reason:
                'Down must cross installed rows and build the final installable rule');
        for (var i = 0;
            i < names.length + 8 && focusedRule() != names.first;
            i++) {
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
          await tester.pumpAndSettle();
        }
        expect(focusedRule(), names.first);
        for (var i = 0;
            i < names.length + 8 && focusedRule() != names.last;
            i++) {
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
          await tester.pumpAndSettle();
        }
        expect(focusedRule(), names.last);
        await tester.sendKeyEvent(LogicalKeyboardKey.select);
        await tester.pumpAndSettle();
        expect(downloads, [names.last]);
        expect(writes, 1);
        expect(focusedRule(), names.last,
            reason: 'Installing must retain focus on the same rule row');
        await tester.sendKeyEvent(LogicalKeyboardKey.select);
        await tester.pumpAndSettle();
        expect(downloads, [names.last],
            reason: 'Installed row must not download again');
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
        await tester.pumpAndSettle();
        expect(focusedRule(), names[names.length - 2]);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pumpAndSettle();
        expect(focusedRule(), names.last);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pumpAndSettle();
        expect(footerFocus.hasFocus, isTrue);
        await tester.pump(const Duration(milliseconds: 2500));
        await tester.pumpAndSettle();
        expect(footerFocus.hasFocus, isTrue,
            reason: 'Idle footer must retain focus before returning to the list');
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
        await tester.pumpAndSettle();
        expect(focusedRule(), names.last);
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.text('Entry'), findsOneWidget);
        expect(find.byType(PluginCatalogView), findsNothing);
        expect(returnFocus.hasFocus, isTrue);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        returnFocus.dispose();
        footerFocus.dispose();
      });
    }
  }
}
