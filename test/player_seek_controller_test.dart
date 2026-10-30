import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/pages/player/controller/player_danmaku_controller.dart';
import 'package:kazumi/pages/player/controller/player_playback_controller.dart';
import 'package:kazumi/pages/player/controller/player_seek_controller.dart';
import 'package:media_kit/media_kit.dart';

class SlowPlayer implements Player {
  final targets = <Duration>[];
  final gates = <Completer<void>>[];
  @override
  Future<void> seek(Duration target) {
    targets.add(target);
    final gate = Completer<void>();
    gates.add(gate);
    return gate.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class Playback implements PlayerPlaybackController {
  @override
  Player? mediaPlayer = SlowPlayer();
  @override
  Duration currentPosition = Duration.zero;
  @override
  Duration duration = const Duration(minutes: 10);
  @override
  bool isCurrentPlayer(Player player) => identical(player, mediaPlayer);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class Danmaku implements PlayerDanmakuController {
  int invalidations = 0;
  @override
  void clearAndInvalidateScheduledDanmakus() => invalidations++;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late Playback playback;
  late SlowPlayer player;
  late Danmaku danmaku;
  late PlayerSeekController controller;
  late List<bool> sync;
  late int plays;
  void setup() {
    playback = Playback();
    player = playback.mediaPlayer as SlowPlayer;
    danmaku = Danmaku();
    sync = [];
    plays = 0;
    controller = PlayerSeekController(
      playback: playback,
      danmaku: danmaku,
      pause: ({bool enableSync = true}) async {},
      play: ({bool enableSync = true}) async {
        plays++;
      },
      onSeekCompleted: (enabled) async {
        sync.add(enabled);
      },
    );
  }

  testWidgets('20 slow seeks execute first and newest, with only final sync',
      (tester) async {
    setup();
    final operations = <Future<void>>[];
    for (var i = 0; i < 20; i++) {
      operations.add(controller.seekBy(const Duration(seconds: 10)));
      await tester.pump();
    }
    expect(playback.currentPosition, const Duration(seconds: 200));
    expect(player.targets, [const Duration(seconds: 10)]);
    player.gates.first.complete();
    await tester.pump();
    expect(player.targets,
        [const Duration(seconds: 10), const Duration(seconds: 200)]);
    expect(sync, isEmpty);
    player.gates.last.complete();
    await tester.pump();
    await Future.wait(operations);
    expect(sync, [true]);
    expect(danmaku.invalidations, 20);
  });

  testWidgets('reverse and clamp use latest target and its sync policy',
      (tester) async {
    setup();
    final first = controller.seekTo(const Duration(seconds: 50));
    await tester.pump();
    final skipped = controller.seekTo(const Duration(hours: 1));
    expect(playback.currentPosition, playback.duration);
    final last =
        controller.seekBy(const Duration(minutes: -20), enableSync: false);
    player.gates.first.complete();
    await tester.pump();
    expect(player.targets.last, Duration.zero);
    player.gates.last.complete();
    await tester.pump();
    await Future.wait([first, skipped, last]);
    expect(sync, [false]);
  });

  testWidgets(
      'new player does not wait for old seek and old pending is retired',
      (tester) async {
    setup();
    final old = controller.seekTo(const Duration(seconds: 10));
    await tester.pump();
    final stale = controller.seekTo(const Duration(seconds: 20));
    final replacement = SlowPlayer();
    playback.mediaPlayer = replacement;
    final current = controller.seekTo(const Duration(seconds: 30));
    await tester.pump();
    expect(replacement.targets, [const Duration(seconds: 30)]);
    await stale;
    replacement.gates.single.complete();
    await tester.pump();
    await current;
    player.gates.single.complete();
    await tester.pump();
    await old;
    expect(player.targets, [const Duration(seconds: 10)]);
    expect(sync, [true]);
  });

  testWidgets(
      'native failure drains latest request and interactive commit stays single',
      (tester) async {
    setup();
    final failed = controller.seekTo(const Duration(seconds: 10));
    await tester.pump();
    controller.beginInteractiveSeek();
    controller.updateInteractiveSeek(const Duration(seconds: 90));
    final committed = controller.commitInteractiveSeek();
    expect(identical(committed, controller.commitInteractiveSeek()), isTrue);
    await tester.pump();
    player.gates.first.completeError(StateError('synthetic native failure'));
    await tester.pump();
    expect(player.targets.last, const Duration(seconds: 90));
    player.gates.last.complete();
    await tester.pump();
    await failed;
    expect(await committed, isTrue);
    expect(plays, 1);
    expect(sync, [true]);
    expect(controller.hasActiveInteractiveSeek, isFalse);
  });

  testWidgets('sync failure reaches caller without blocking a later seek',
      (tester) async {
    setup();
    var attempts = 0;
    controller = PlayerSeekController(
      playback: playback,
      danmaku: danmaku,
      pause: ({bool enableSync = true}) async {},
      play: ({bool enableSync = true}) async {},
      onSeekCompleted: (_) async {
        if (++attempts == 1) throw StateError('synthetic sync failure');
      },
    );
    final failed = expectLater(
        controller.seekTo(const Duration(seconds: 10)), throwsStateError);
    player.gates.single.complete();
    await tester.pump();
    await failed;
    final next = controller.seekTo(const Duration(seconds: 20));
    player.gates.last.complete();
    await tester.pump();
    await next;
    expect(attempts, 2);
  });

  testWidgets('invalidated interactive commit does not seek or resume',
      (tester) async {
    setup();
    controller.beginInteractiveSeek();
    controller.updateInteractiveSeek(const Duration(seconds: 90));
    final commit = controller.commitInteractiveSeek();
    controller.invalidateInteractiveSeek();
    await tester.pump();
    expect(await commit, isFalse);
    expect(player.targets, isEmpty);
    expect(plays, 0);
    playback.mediaPlayer = null;
    await controller.seekTo(Duration.zero);
    expect(danmaku.invalidations, 0);
  });
}
