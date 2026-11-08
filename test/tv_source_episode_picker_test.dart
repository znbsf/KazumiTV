import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/modules/roads/road_module.dart';
import 'package:kazumi/pages/info/source_episode_picker.dart';
import 'package:kazumi/pages/video/video_playback_args.dart';
import 'package:kazumi/plugins/plugins.dart';
import 'package:kazumi/services/platform/tv_mode.dart';
import 'package:kazumi/services/player/cross_source_resume.dart';

import 'support/tv_focus_fixtures.dart' show focusItem;

OnlineVideoPlaybackArgs _target(List<Road> roads) => OnlineVideoPlaybackArgs(
  bangumiItem: focusItem(1),
  plugin: Plugin.fromJson({'name': 'new', 'baseURL': 'https://new.test'}),
  title: 'Target',
  src: '/work',
  roads: roads,
  transfer: const CrossSourceResume(
    bangumiId: 1, pluginName: 'new', src: '/work', road: 1, episode: 2,
    episodePageUrl: 'https://new.test/old', offset: 70,
  ),
);

List<Road> _roads() => [
  Road(name: '线路一', data: ['/1', '/2'], identifier: ['第一集', '第二集']),
  Road(name: '线路二', data: ['/3', '/4'], identifier: ['第三集', '第四集']),
];

Future<void> _open(WidgetTester tester, OnlineVideoPlaybackArgs target,
    {double scale = 1, void Function(CrossSourceResume?)? onResult}) async {
  await tester.pumpWidget(MaterialApp(
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
      child: child!,
    ),
    home: Scaffold(body: Builder(builder: (context) => TextButton(
      onPressed: () async {
        final result = await showDialog<CrossSourceResume>(
          context: context, builder: (_) => SourceEpisodePicker(target: target));
        onResult?.call(result);
      },
      child: const Text('打开'),
    ))),
  ));
  await tester.tap(find.text('打开'));
  await tester.pumpAndSettle();
}

bool _focused(WidgetTester tester, Finder finder) =>
    tester.widget<TextButton>(finder).focusNode!.hasPrimaryFocus;

void main() {
  tearDown(() => TvMode.setEnabledForTesting(false));

  for (final size in [const Size(960, 540), const Size(1280, 720)]) {
    for (final scale in [1.0, 1.3]) {
      testWidgets('TV picker navigates and fits $size at $scale', (tester) async {
        TvMode.setEnabledForTesting(true);
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        CrossSourceResume? result;
        await _open(tester, _target(_roads()), scale: scale, onResult: (value) => result = value);
        final first = find.byKey(const ValueKey('source-episode-0-1'));
        expect(_focused(tester, first), isTrue);
        expect(find.text('线路一 · 2集'), findsOneWidget);
        expect(find.text('线路二 · 2集'), findsOneWidget);
        expect(find.text('第三集'), findsNothing);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
        await tester.pumpAndSettle();
        expect(_focused(tester, find.byKey(const ValueKey('source-road-0'))), isTrue);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pumpAndSettle();
        expect(_focused(tester, find.byKey(const ValueKey('source-road-1'))), isTrue);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pumpAndSettle();
        expect(_focused(tester, find.byKey(const ValueKey('source-episode-1-1'))), isTrue);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pumpAndSettle();
        final chosen = find.byKey(const ValueKey('source-episode-1-2'));
        expect(_focused(tester, chosen), isTrue);
        expect(tester.getRect(find.byKey(const ValueKey('source-grid-1')))
            .contains(tester.getCenter(chosen)), isTrue);
        expect(tester.takeException(), isNull);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(result!.road, 1);
        expect(result!.episode, 2);
        expect(result!.episodePageUrl, 'https://new.test/4');
        expect(result!.offset, 0);
      });
    }
  }

  for (final scale in [1.0, 1.3]) {
    testWidgets('manual picker labels only overflow and stay below title at $scale',
        (tester) async {
      TvMode.setEnabledForTesting(true);
      tester.view.physicalSize = const Size(960, 540);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const long = '这是一个需要完整显示的非常非常长的剧集名称用于检查截断提示位置';
      await _open(tester, _target([
        Road(name: '线路', data: ['/1', '/2'], identifier: ['第一集', long]),
      ]), scale: scale);
      expect(find.text('第一集'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(find.text(long), findsNWidgets(2));
      final overlay = find.text(long).last;
      expect(tester.getRect(overlay).top,
          greaterThan(tester.getRect(find.text('选择新源集数')).bottom));
      expect(tester.getRect(overlay).top, greaterThanOrEqualTo(
          tester.getRect(find.byKey(const ValueKey('source-episode-0-2'))).bottom));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(find.text('第一集'), findsOneWidget);
      expect(find.text(long), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('single playable road hides road list and skips empty URLs', (tester) async {
    TvMode.setEnabledForTesting(true);
    await _open(tester, _target([
      Road(name: '空线路', data: [], identifier: []),
      Road(name: '唯一线路', data: ['', '/2'], identifier: ['不可播放', '可播放']),
    ]));
    expect(find.byKey(const ValueKey('source-road-1')), findsNothing);
    expect(find.text('不可播放'), findsNothing);
    expect(_focused(tester, find.byKey(const ValueKey('source-episode-1-2'))), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('long grid keeps the remote focused item visible', (tester) async {
    TvMode.setEnabledForTesting(true);
    tester.view.physicalSize = const Size(960, 540);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _open(tester, _target([
      Road(name: '长线路', data: List.generate(60, (i) => '/$i'),
          identifier: List.generate(60, (i) => '第 $i 集 较长的标题')),
    ]), scale: 1.3);
    for (var i = 0; i < 8; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
    }
    final focused = find.byWidgetPredicate((widget) => widget is TextButton &&
        widget.focusNode?.hasPrimaryFocus == true);
    expect(focused, findsOneWidget);
    final viewport = tester.getRect(find.byKey(const ValueKey('source-grid-0')));
    final rect = tester.getRect(focused);
    expect(rect.top, greaterThanOrEqualTo(viewport.top));
    expect(rect.bottom, lessThanOrEqualTo(viewport.bottom));
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty result focuses return and Escape returns null', (tester) async {
    TvMode.setEnabledForTesting(true);
    var returned = false;
    CrossSourceResume? result;
    await _open(tester, _target([]), onResult: (value) { returned = true; result = value; });
    expect(find.text('此结果没有可播放集数，请返回选择其他结果'), findsOneWidget);
    final button = tester.widget<TextButton>(find.widgetWithText(TextButton, '返回选源'));
    expect(button.autofocus, isTrue);
    expect(Focus.of(tester.element(find.text('返回选源'))).hasPrimaryFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(returned, isTrue);
    expect(result, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('non-TV retains flattened list', (tester) async {
    TvMode.setEnabledForTesting(false);
    await _open(tester, _target(_roads()));
    expect(find.text('线路一 · 第一集 · 从头播放'), findsOneWidget);
    expect(find.text('线路二 · 第三集 · 从头播放'), findsOneWidget);
    expect(find.byKey(const ValueKey('source-road-0')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
