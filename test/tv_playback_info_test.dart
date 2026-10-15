import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/modules/roads/road_module.dart';
import 'package:kazumi/pages/player/player_keyboard_shortcuts.dart';
import 'package:kazumi/pages/player/tv_playback_info.dart';

TvPlaybackInfoData data(
        {List<String> labels = const ['01', '02'], int index = 1}) =>
    TvPlaybackInfoData.fromPlayback(
      title: '番剧名',
      fallbackTitle: '来源标题',
      sourceName: '测试源',
      images: const {},
      roads: [
        Road(
            name: '路线',
            data: labels.map((e) => '/$e').toList(),
            identifier: labels)
      ],
      roadIndex: 0,
      episodeIndex: index,
    );

void main() {
  test('only reliable adjacent episode labels become next episode', () {
    expect(data().episode, '01');
    expect(data().nextEpisode, '02');
    expect(data(index: 2).nextEpisode, isNull);
    expect(data(labels: ['SP01', '02']).nextEpisode, isNull);
    expect(data(labels: ['01', '03']).nextEpisode, isNull);
    expect(data(labels: ['01', '02', '02']).nextEpisode, isNull);
    expect(data(labels: ['01', '02', '01']).nextEpisode, isNull);
    expect(data(index: 8).episode, '集数暂不可用');
  });

  test(
      'missing titles and mismatched roads degrade without borrowing another episode',
      () {
    final info = TvPlaybackInfoData.fromPlayback(
      title: ' ',
      fallbackTitle: '来源标题',
      sourceName: ' ',
      images: const {},
      roads: [
        Road(name: '', data: ['/one'], identifier: ['01', '02'])
      ],
      roadIndex: 0,
      episodeIndex: 2,
    );
    expect(info.title, '来源标题');
    expect(info.sourceName, isEmpty);
    expect(info.episode, '集数暂不可用');
    expect(info.nextEpisode, isNull);
    expect(info.coverUrl, isEmpty);
  });

  testWidgets(
      'one INFO route restores focus repeatedly without toggling playback',
      (tester) async {
    final presenter = TvPlaybackInfoPresenter();
    final scope = FocusScopeNode();
    final button = FocusNode();
    addTearDown(scope.dispose);
    addTearDown(button.dispose);
    addTearDown(presenter.close);
    var playing = true;
    late BuildContext owner;
    void open() => unawaited(presenter.show(owner,
        fallbackFocus: button,
        builder: (_) =>
            TvPlaybackInfoCard(info: data(), onClose: presenter.close)));
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) {
      owner = context;
      return Scaffold(
          body: FocusScope(
              node: scope,
              child: Column(children: [
                PlayerKeyboardShortcuts(
                    focusScopeNode: scope,
                    shortcuts: withTvRemoteShortcuts({}),
                    actions: {
                      'showdetails': open,
                      'playorpause': () => playing = !playing
                    }),
                TextButton(
                    focusNode: button,
                    onPressed: open,
                    child: const Text('INFO')),
              ])));
    })));
    for (final initiallyPlaying in [true, false, true]) {
      playing = initiallyPlaying;
      button.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.info);
      await tester.pumpAndSettle();
      expect(find.byType(TvPlaybackInfoCard), findsOneWidget);
      open(); // Duplicate requests cannot stack dialogs.
      await tester.pumpAndSettle();
      expect(find.byType(TvPlaybackInfoCard), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.mediaPlayPause);
      expect(playing, initiallyPlaying);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(TvPlaybackInfoCard), findsNothing);
      expect(button.hasFocus, isTrue);
      expect(playing, initiallyPlaying);
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.colorF3Blue,
        physicalKey: PhysicalKeyboardKey.f3);
    await tester.pumpAndSettle();
    await tester
        .sendKeyEvent(LogicalKeyboardKey.enter); // Focused return action.
    await tester.pumpAndSettle();
    expect(button.hasFocus, isTrue);
    open();
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(presenter.isOpen, isFalse);
    expect(button.hasFocus, isTrue);
    open();
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.info);
    await tester.pumpAndSettle();
    expect(presenter.isOpen, isFalse);
    open();
    await tester.pumpAndSettle();
    unawaited(showDialog<void>(
        context: owner,
        builder: (_) => const AlertDialog(content: Text('Other modal'))));
    await tester.pumpAndSettle();
    presenter.close();
    await tester.pumpAndSettle();
    expect(find.text('Other modal'), findsOneWidget);
    expect(presenter.isOpen, isFalse);
    Navigator.of(tester.element(find.text('Other modal'))).pop();
    await tester.pumpAndSettle();
    button.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.mediaPlayPause);
    expect(playing, isFalse); // No stale modal/key ownership after closing.
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('route cleanup during a frame waits for navigator reconciliation',
      (tester) async {
    final presenter = TvPlaybackInfoPresenter();
    final focus = FocusNode();
    final closing = ValueNotifier(false);
    addTearDown(focus.dispose);
    addTearDown(closing.dispose);
    late BuildContext owner;
    await tester.pumpWidget(MaterialApp(
        home: ValueListenableBuilder<bool>(
            valueListenable: closing,
            builder: (context, close, _) {
              owner = context;
              if (close) presenter.close();
              return const Scaffold(body: Text('Player'));
            })));
    unawaited(presenter.show(owner,
        fallbackFocus: focus,
        builder: (_) =>
            TvPlaybackInfoCard(info: data(), onClose: presenter.close)));
    await tester.pumpAndSettle();
    closing.value = true;
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(presenter.isOpen, isFalse);
    expect(find.text('Player'), findsOneWidget);
  });

  for (final brightness in Brightness.values) {
    testWidgets('compact card respects $brightness theme and large text',
        (tester) async {
      tester.view.resetPhysicalSize();
      tester.view.physicalSize = const Size(640, 360);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final theme =
          ThemeData(colorSchemeSeed: Colors.teal, brightness: brightness);
      await tester.pumpWidget(MaterialApp(
          theme: theme,
          home: MediaQuery(
            data: const MediaQueryData(
                size: Size(640, 360), textScaler: TextScaler.linear(1.5)),
            child: TvPlaybackInfoCard(
                info: data(labels: ['很长的单集标题' * 10]), onClose: () {}),
          )));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final surface = tester.widget<ColoredBox>(
          find.byKey(const ValueKey('playback-info-surface')));
      expect(surface.color, theme.colorScheme.surface.withValues(alpha: .64));
      expect(find.text('返回播放'), findsOneWidget);
    });
  }
}
