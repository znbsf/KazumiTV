import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:kazumi/pages/search/image_search_page.dart';
import 'package:kazumi/services/platform/tv_mode.dart';
import 'package:kazumi/services/storage/storage.dart';

import 'support/tv_focus_fixtures.dart';

class _Paths extends PathProviderPlatform {
  _Paths(this.path);
  final String path;
  @override
  Future<String?> getApplicationSupportPath() async => path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  late PathProviderPlatform originalPaths;
  setUpAll(() async {
    temp = await Directory.systemTemp.createTemp('kazumi_image_picker_');
    originalPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _Paths(temp.path);
    Hive.init(temp.path);
    await GStorage.init();
  });
  tearDownAll(() async {
    await Hive.close();
    PathProviderPlatform.instance = originalPaths;
    await temp.delete(recursive: true);
  });
  const channel = MethodChannel('com.predidit.kazumi/intent');
  const message = '这台电视没有系统图片选择器，请改用“图片链接”';
  const pickerChannel = MethodChannel('plugins.flutter.io/image_picker');
  late int pickerCalls;

  setUp(() {
    TvMode.setEnabledForTesting(true);
    pickerCalls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pickerChannel, (call) async {
      pickerCalls++;
      return null; // A normal picker cancellation, without file or network IO.
    });
  });
  tearDown(() {
    TvMode.setEnabledForTesting(false);
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, null);
    messenger.setMockMethodCallHandler(pickerChannel, null);
  });

  for (final scenario in ['missing', 'available', 'throws', 'phone']) {
    testWidgets('image picker availability: $scenario', (tester) async {
      var queries = 0;
      TvMode.setEnabledForTesting(scenario != 'phone');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
          (call) async {
        expect(call.method, 'canPickImage');
        queries++;
        if (scenario == 'throws') throw PlatformException(code: 'unavailable');
        return scenario == 'available';
      });
      await tester.pumpWidget(MaterialApp(
          home: ImageSearchPage(controller: FocusSearchController())));
      await tester.pumpAndSettle();
      final action = find.widgetWithText(FilledButton, '选择截图');
      await tester.ensureVisible(action);
      await tester.tap(action);
      await tester.pumpAndSettle();
      final blocked = scenario == 'missing' || scenario == 'throws';
      expect(pickerCalls, blocked ? 0 : 1);
      expect(queries, scenario == 'phone' ? 0 : 1);
      expect(find.text(message), blocked ? findsOneWidget : findsNothing);
      if (scenario != 'phone') {
        expect(tester.widget<FilledButton>(action).focusNode!.hasPrimaryFocus,
            isTrue);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
