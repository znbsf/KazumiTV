import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:kazumi/pages/settings/danmaku/danmaku_time_offset_sheet.dart';
import 'package:kazumi/services/platform/tv_mode.dart';
import 'package:kazumi/services/storage/storage.dart';

class _Paths extends PathProviderPlatform {
  _Paths(this.path);
  final String path;
  @override
  Future<String?> getApplicationSupportPath() async => path;
}

Future<void> _key(WidgetTester tester, LogicalKeyboardKey key,
    [int count = 1]) async {
  for (var i = 0; i < count; i++) {
    await tester.runAsync(() => tester.sendKeyEvent(key));
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

double _value(WidgetTester tester) =>
    tester.widget<Slider>(find.byType(Slider)).value;
FocusNode _button(WidgetTester tester, IconData icon) =>
    Focus.of(tester.element(find.byIcon(icon)));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late PathProviderPlatform oldPaths;
  setUpAll(() async {
    oldPaths = PathProviderPlatform.instance;
    dir = await Directory.systemTemp.createTemp('offset_history_');
    PathProviderPlatform.instance = _Paths(dir.path);
    Hive.init(dir.path);
    await GStorage.init();
  });
  tearDownAll(() async {
    await Hive.close();
    PathProviderPlatform.instance = oldPaths;
    await dir.delete(recursive: true);
  });
  setUp(() => TvMode.setEnabledForTesting(true));
  tearDown(() => TvMode.setEnabledForTesting(false));
  Future<void> mount(
      WidgetTester tester, double value, VoidCallback changed) async {
    await tester.runAsync(
        () => GStorage.putSetting(SettingsKeys.danmakuTimeOffset, value));
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Center(
                child: SizedBox(
                    width: 600,
                    height: 480,
                    child: DanmakuTimeOffsetSheet(
                        onTimelineOffsetChanged: changed))))));
    await tester.pumpAndSettle();
  }

  testWidgets(
      'actual offset sheet skips remembered plus button after it becomes disabled',
      (tester) async {
    var changes = 0;
    await mount(tester, 0, () => changes++);
    _button(tester, Icons.add_rounded).requestFocus();
    await tester.pump();
    await _key(tester, LogicalKeyboardKey.arrowDown);
    await _key(tester, LogicalKeyboardKey.arrowLeft, 18);
    expect(_value(tester), -180);
    await _key(tester, LogicalKeyboardKey.arrowUp);
    expect(_button(tester, Icons.add_rounded).hasPrimaryFocus, isTrue);
    await _key(tester, LogicalKeyboardKey.arrowDown);
    await _key(tester, LogicalKeyboardKey.arrowRight, 36);
    expect(_value(tester), 180);
    final before = changes;
    await _key(tester, LogicalKeyboardKey.arrowUp);
    expect(_button(tester, Icons.remove_rounded).hasPrimaryFocus, isTrue);
    expect(changes, before);
    expect(_value(tester), 180);
    // Reverse the same history at the opposite bound.
    await _key(tester, LogicalKeyboardKey.arrowDown);
    await _key(tester, LogicalKeyboardKey.arrowLeft, 36);
    await _key(tester, LogicalKeyboardKey.arrowUp);
    expect(_button(tester, Icons.add_rounded).hasPrimaryFocus, isTrue);
  });
  testWidgets(
      'actual offset reset becoming disabled releases focus and Down reaches slider',
      (tester) async {
    await mount(tester, 10, () {});
    final reset = Focus.of(tester.element(find.text('恢复同步')));
    _button(tester, Icons.remove_rounded).requestFocus();
    await tester.pump();
    await _key(tester, LogicalKeyboardKey.arrowDown);
    await _key(tester, LogicalKeyboardKey.arrowDown);
    expect(reset.hasPrimaryFocus, isTrue);
    await _key(tester, LogicalKeyboardKey.enter);
    expect(_value(tester), 0);
    expect(reset.hasPrimaryFocus, isFalse);
    await _key(tester, LogicalKeyboardKey.arrowDown);
    expect(_value(tester), 0);
    await _key(tester, LogicalKeyboardKey.arrowRight);
    expect(_value(tester), 10);
  });
}
