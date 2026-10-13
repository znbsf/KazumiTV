import 'package:kazumi/pages/settings/sync/bangumi_sync_page.dart';
import 'package:kazumi/pages/player/syncplay_sheet.dart';
import 'package:kazumi/pages/player/player_controller.dart';
import 'package:kazumi/pages/player/controller/player_syncplay_controller.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kazumi/pages/settings/proxy/proxy_editor_page.dart';
import 'package:kazumi/pages/settings/sync/webdav_server_page.dart';
import 'package:kazumi/services/platform/tv_mode.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _Paths extends PathProviderPlatform {
  _Paths(this.path);
  final String path;
  @override
  Future<String?> getApplicationSupportPath() async => path;
}

class _SyncState implements PlayerSyncPlayController {
  @override
  bool get hasSession => false;
  @override
  String get syncplayRoom => '';
  @override
  int get syncplayClientRtt => 0;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Player implements PlayerController {
  @override
  final syncplay = _SyncState();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('kazumi_tv_forms_');
    PathProviderPlatform.instance = _Paths(directory.path);
    Hive.init(directory.path);
    await GStorage.init();
  });
  tearDownAll(() async {
    await Hive.close();
    await directory.delete(recursive: true);
  });
  setUp(() => TvMode.setEnabledForTesting(true));
  tearDown(() => TvMode.setEnabledForTesting(false));
  for (final scene in <String, Widget>{
    'proxy': const ProxyEditorPage(),
    'webdav': const WebDavServerPage()
  }.entries) {
    testWidgets(
        '${scene.key} navigation exposes no editable; OK edits and invalid values still validate',
        (tester) async {
      await tester.pumpWidget(MaterialApp(home: scene.value));
      await tester.pumpAndSettle();
      expect(find.byType(EditableText), findsNothing,
          reason: 'TV form navigation must require explicit editing');
      final form = tester.state<FormState>(find.byType(Form));
      expect(form.validate(), isFalse);
      await tester.pump();
      final target = find.byType(InputDecorator).first;
      await tester.tap(target);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.enterText(
          find.byKey(const Key('tv-text-editor')), 'invalid');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(form.validate(), isFalse);
      expect(find.byType(EditableText), findsNothing);
      expect(tester.testTextInput.isVisible, isFalse);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets(
      'Bangumi token only edits on activation; cancel and empty submit remain local',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: BangumiSyncPage()));
    await tester.pumpAndSettle();
    final tile = find.byType(ExpansionTile).first;
    if (find.byType(InputDecorator).evaluate().isEmpty) {
      await tester.ensureVisible(tile);
      await tester.tap(
          find.descendant(of: tile, matching: find.byType(ListTile)).first);
      await tester.pumpAndSettle();
    }
    expect(find.byType(EditableText), findsNothing);
    final input = find.byType(InputDecorator).first;
    await tester.ensureVisible(input);
    await tester.tap(input);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(
        tester
            .widget<TextField>(find.byKey(const Key('tv-text-editor')))
            .obscureText,
        isTrue);
    await tester.enterText(
        find.byKey(const Key('tv-text-editor')), 'cancel-token');
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('cancel-token'), findsNothing);
    await tester.tap(input);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('tv-text-editor')), '');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(EditableText), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'Syncplay join step uses explicit field activation and preserves room validator',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => Scaffold(
                body: TextButton(
                    onPressed: () => showSyncPlaySheet(context,
                        playerController: _Player(),
                        changeEpisode: (episode,
                            {currentRoad = 0, offset = 0}) async {}),
                    child: const Text('open'))))));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.login_rounded));
    await tester.pumpAndSettle();
    expect(find.byType(EditableText), findsNothing);
    expect(tester.testTextInput.isVisible, isFalse);
    final form = tester.state<FormState>(find.byType(Form));
    expect(form.validate(), isFalse);
    await tester.pump();
    await tester.tap(find.byType(InputDecorator).first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('tv-text-editor')), '12abc');
    await tester.testTextInput.receiveAction(TextInputAction.next);
    await tester.pumpAndSettle();
    expect(form.validate(), isFalse);
    expect(find.text('12'), findsOneWidget);
    expect(find.byType(EditableText), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'Syncplay custom server selection stays in navigation until field activation',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => Scaffold(
                body: TextButton(
                    onPressed: () => showSyncPlaySheet(context,
                        playerController: _Player(),
                        changeEpisode: (episode,
                            {currentRoad = 0, offset = 0}) async {}),
                    child: const Text('open'))))));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.chevron_right_rounded));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();
    expect(find.byType(EditableText), findsNothing);
    expect(tester.testTextInput.isVisible, isFalse);
    final input = find.byType(InputDecorator);
    await tester.ensureVisible(input);
    await tester.tap(input);
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('tv-text-editor')), 'example.test:8996');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.text('example.test:8996'), findsOneWidget);
    expect(find.byType(EditableText), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
