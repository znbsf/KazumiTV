import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/modules/roads/road_module.dart';
import 'package:kazumi/pages/info/source_episode_picker.dart';
import 'package:kazumi/pages/video/video_playback_args.dart';
import 'package:kazumi/plugins/plugins.dart';
import 'package:kazumi/services/player/cross_source_resume.dart';
import 'package:kazumi/services/player/episode_identity.dart';
import 'package:kazumi/services/player/source_switch.dart';
import 'package:kazumi/services/video_source/video_source_service.dart';
import 'support/tv_focus_fixtures.dart' show focusItem;

class _Resolver implements IVideoSourceService {
  final pending = <Completer<VideoSource>>[];
  int cancellations = 0;
  @override
  Future<VideoSource> resolve(String url,
      {required bool useLegacyParser,
      int offset = 0,
      Duration timeout = const Duration(seconds: 30)}) {
    final result = Completer<VideoSource>();
    pending.add(result);
    return result.future;
  }

  @override
  void cancel() => cancellations++;
  @override
  Future<void> dispose() async {}
}

void main() {
  final target = OnlineVideoPlaybackArgs(
    bangumiItem: focusItem(1),
    plugin: Plugin.fromJson({'name': 'new', 'baseURL': 'https://new.test'}),
    title: 'Target',
    src: '/work',
    roads: [
      Road(name: '逆序', data: ['/2', '/1'], identifier: ['EP02', '第1集'])
    ],
    transfer: const CrossSourceResume(
        bangumiId: 1,
        pluginName: 'new',
        src: '/work',
        road: 0,
        episode: 1,
        episodePageUrl: 'https://new.test/2',
        offset: 70),
  );
  const resolved = VideoSource(
      url: 'https://media.test/play.mp4',
      offset: 70,
      type: VideoSourceType.online);

  test('live snapshot matches semantic episode on a reordered road', () {
    const origin = SourceSwitchOrigin(
        episode: EpisodeIdentity(title: '第2集', pageUrl: '/old/2'), offset: 70);
    final choices = origin.choices(target);
    expect(choices.single.episode, 1);
    expect(choices.single.offset, 70);
    expect(choices.single.episodePageUrl, 'https://new.test/2');
    expect(const SourceSwitchOrigin(episode: null, offset: 70).choices(target),
        isEmpty);
    expect(
        const SourceSwitchOrigin(
                episode: EpisodeIdentity(title: 'SP2', pageUrl: '/old/sp'),
                offset: 70)
            .choices(target),
        isEmpty);
  });

  test('parser failure propagates without producing a commit', () async {
    final backend = _Resolver();
    final resolver = SourceSwitchResolver(backend);
    final request = resolver.prepare(target);
    final expectation =
        expectLater(request, throwsA(isA<VideoSourceTimeoutException>()));
    backend.pending.single.completeError(
        const VideoSourceTimeoutException(Duration(seconds: 30)));
    await expectation;
    await resolver.dispose();
  });

  for (final action in ['cancel', 'dispose', 'replace']) {
    test('$action rejects a late parser result', () async {
      final backend = _Resolver();
      final resolver = SourceSwitchResolver(backend);
      final first = resolver.prepare(target);
      final expectation =
          expectLater(first, throwsA(isA<VideoSourceCancelledException>()));
      Future<PreparedSourceSwitch>? replacement;
      if (action == 'cancel') resolver.cancel();
      if (action == 'dispose') await resolver.dispose();
      if (action == 'replace') replacement = resolver.prepare(target);
      backend.pending.first.complete(resolved);
      await expectation;
      if (replacement != null) {
        backend.pending.last.complete(resolved);
        expect((await replacement).args, same(target));
      }
      if (action != 'dispose') await resolver.dispose();
    });
  }

  testWidgets('manual episode selection owns arrows and starts at zero',
      (tester) async {
    CrossSourceResume? result;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Builder(
                builder: (context) => TextButton(
                      autofocus: true,
                      onPressed: () async {
                        result = await showDialog<CrossSourceResume>(
                            context: context,
                            builder: (_) =>
                                SourceEpisodePicker(target: target));
                      },
                      child: const Text('选源'),
                    )))));
    final origin = FocusManager.instance.primaryFocus;
    await tester.tap(find.text('选源'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(result!.episode, 1);
    expect(result!.offset, 0);
    expect(FocusManager.instance.primaryFocus, same(origin));
    await tester.tap(find.text('选源'));
    await tester.pumpAndSettle();
    result = null;
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(result, isNull);
    expect(FocusManager.instance.primaryFocus, same(origin));
    expect(tester.takeException(), isNull);
  });
}
