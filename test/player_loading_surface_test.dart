import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:mobx/mobx.dart';
import 'package:kazumi/pages/player/player_controller.dart';
import 'package:kazumi/pages/player/player_item_surface.dart';
import 'package:kazumi/pages/player/controller/player_playback_controller.dart';
import 'package:kazumi/pages/player/controller/player_panel_controller.dart';
import 'package:kazumi/pages/player/controller/player_debug_controller.dart';
import 'package:kazumi/services/shaders/shader_asset_service.dart';

class _Shader implements ShaderAssetService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Owner implements PlayerController {
  @override
  final panel = PlayerPanelController();
  @override
  final playback = PlayerPlaybackController(
      shaderAssetService: _Shader(),
      debug: PlayerDebugController(),
      videoUrl: () => '',
      isLocalPlayback: () => true);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Streams implements PlayerStream {
  @override
  Stream<int?> get width => const Stream.empty();
  @override
  Stream<int?> get height => const Stream.empty();
  @override
  Stream<bool> get playing => const Stream.empty();
  @override
  Stream<List<String>> get subtitle => const Stream.empty();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Player implements Player {
  @override
  PlayerState get state => const PlayerState(width: 640, height: 360);
  @override
  final stream = _Streams();
  @override
  PlatformPlayer? platform;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Platform extends PlatformVideoController {
  _Platform(Player player, int texture)
      : super(player, const VideoControllerConfiguration()) {
    id.value = texture;
    rect.value = const Rect.fromLTWH(0, 0, 640, 360);
  }
  @override
  Future<void> setSize({int? width, int? height}) async {}
}

class _Controller implements VideoController {
  _Controller(int texture) {
    output = _Platform(player, texture);
    notifier = ValueNotifier(output);
  }
  @override
  final player = _Player();
  late final _Platform output;
  @override
  late final ValueNotifier<PlatformVideoController?> notifier;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUp(() {
    final previous = mainContext.config;
    mainContext.config =
        ReactiveConfig(writePolicy: ReactiveWritePolicy.always);
    addTearDown(() => mainContext.config = previous);
  });
  testWidgets(
      'loading renders real Video Texture under interactive overlay; new output and null react',
      (tester) async {
    final owner = _Owner();
    var cancelled = false;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Stack(children: [
      Positioned.fill(
          child: IgnorePointer(
              child: ExcludeFocus(
                  child: PlayerItemSurface(playerController: owner)))),
      Positioned.fill(
          child: ColoredBox(
              color: Colors.black.withValues(alpha: .99),
              child: Center(
                  child: TextButton(
                      onPressed: () => cancelled = true,
                      child: const Text('Cancel loading'))))),
    ]))));
    expect(owner.playback.loading, isTrue);
    expect(find.byType(Texture), findsNothing);
    final first = _Controller(41);
    owner.playback.videoController ??= first;
    await tester.pump();
    // Use the actual media-kit Video/Texture widgets and rendering layer.
    // Native output metadata alone is faked; no first-frame completion is faked.
    expect(find.byType(Video), findsOneWidget);
    expect(tester.widget<Texture>(find.byType(Texture)).textureId, 41);
    expect(
        tester.layers.whereType<TextureLayer>().any((l) => l.textureId == 41),
        isTrue);
    await tester.tap(find.text('Cancel loading'));
    expect(cancelled, isTrue);
    final replacement = _Controller(42);
    await Future<void>.value();
    owner.playback.videoController = replacement;
    await tester.pump();
    expect(tester.widget<Texture>(find.byType(Texture)).textureId, 42);
    // Exercise the real production cleanup path that failed on device. Do not
    // wrap the call in a test action: the setter must enforce its own boundary.
    await owner.playback.stop();
    await tester.pump();
    expect(find.byType(Texture), findsNothing);
    expect(find.text('Cancel loading'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    first.notifier.dispose();
    first.output.dispose();
    replacement.notifier.dispose();
    replacement.output.dispose();
  });
}
