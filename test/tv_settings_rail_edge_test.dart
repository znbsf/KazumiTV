import 'dart:io';
import 'package:hive_ce/hive.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/bean/widget/tv_focus_navigation.dart';
import 'package:kazumi/pages/settings/settings_module.dart';
import 'package:kazumi/services/platform/tv_mode.dart';

class _Paths extends PathProviderPlatform {
  _Paths(this.path);
  final String path;
  @override
  Future<String?> getApplicationSupportPath() async => path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  setUpAll(() async {
    temp = await Directory.systemTemp.createTemp('rail_edge_');
    PathProviderPlatform.instance = _Paths(temp.path);
    Hive.init(temp.path);
    await GStorage.init();
  });
  tearDownAll(() async {
    await Hive.close();
    await temp.delete(recursive: true);
  });
  testWidgets('actual settings rail wraps from toolbar to final category',
      (tester) async {
    TvMode.setEnabledForTesting(true);
    addTearDown(() => TvMode.setEnabledForTesting(false));
    tester.view.physicalSize = const Size(960, 540);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final module = createModule(register: (c) {
      c.route('/',
          child: (context, _) => Scaffold(
              body: TextButton(
                  onPressed: () => context.pushNamed('/settings/'),
                  child: const Text('Open settings'))));
      c.module(settingsModule);
    });
    await tester.pumpWidget(ModularApp(
        module: module,
        initialRoute: '/',
        child: Builder(
            builder: (context) => MaterialApp.router(
                routerConfig: ModularApp.routerConfigOf(context),
                builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(context)
                        .copyWith(navigationMode: NavigationMode.directional),
                    child: FocusTraversalGroup(
                        policy: TvLoopTraversalPolicy(), child: child!))))));
    await tester.runAsync(() async {
      await tester.pump();
      await tester.tap(find.text('Open settings'));
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    Focus.of(tester.element(find.text('硬件解码'))).requestFocus();
    await tester.pumpAndSettle();
    expect(Focus.of(tester.element(find.text('硬件解码'))).hasPrimaryFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus!.debugLabel,
        'TV settings category /settings/player');
    FocusManager.instance.rootScope.descendants
        .firstWhere((node) =>
            node.debugLabel == 'TV settings category /settings/player')
        .requestFocus();
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus!.debugLabel,
        'TV settings category /settings/about');
    expect(FocusManager.instance.primaryFocus!.rect.bottom,
        lessThanOrEqualTo(540));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus!.debugLabel,
        'TV settings category /settings/player');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus!.debugLabel,
        'TV settings category /settings/about');
    await tester.pumpWidget(const SizedBox());
  });
}
