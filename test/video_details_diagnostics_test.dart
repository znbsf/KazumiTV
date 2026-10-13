import 'package:flutter/services.dart';
import 'package:kazumi/pages/settings/tv_remote_help.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/bean/widget/connected_tabs.dart';
import 'package:kazumi/pages/player/controller/player_debug_controller.dart';
import 'package:kazumi/pages/player/controller/player_diagnostics.dart';
import 'package:kazumi/pages/player/controller/player_playback_controller.dart';
import 'package:kazumi/pages/player/player_controller.dart';
import 'package:kazumi/pages/player/video_details_sheet.dart';
import 'package:kazumi/services/platform/tv_mode.dart';

final _diagnostics = PlayerDiagnosticsSnapshot.fromProperties(
  const {
    'current-vo': 'fixture-gpu',
    'current-gpu-context': 'fixture-android',
    'video-params/pixelformat': 'fixture-yuv420p',
  },
  hardwareAccelerationEnabled: false,
  configuredHardwareDecoder: 'no',
);

// Implements the UI's read boundary without constructing a native Player.
class _FakePlaybackController implements PlayerPlaybackController {
  _FakePlaybackController(this.diagnostics);

  final Future<PlayerDiagnosticsSnapshot> diagnostics;
  int diagnosticsReadCount = 0;

  @override
  Future<PlayerDiagnosticsSnapshot> readDiagnostics() {
    diagnosticsReadCount++;
    return diagnostics;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    throw UnsupportedError(
        'Unexpected playback call: ${invocation.memberName}');
  }
}

class _FakePlayerController implements PlayerController {
  _FakePlayerController(this.playback);

  @override
  final _FakePlaybackController playback;

  // This store only supplies observable UI data. setup() is never called,
  // so it owns no media streams and requires no settings or Hive boxes.
  @override
  final PlayerDebugController debug = PlayerDebugController();

  @override
  String videoUrl = 'test://diagnostics-fixture';

  @override
  dynamic noSuchMethod(Invocation invocation) {
    throw UnsupportedError('Unexpected player call: ${invocation.memberName}');
  }
}

Future<void> _pumpSheet(
  WidgetTester tester,
  _FakePlayerController player, {
  required VideoDetailsTab initialTab,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: VideoDetailsSheet(
        playerController: player,
        initialTab: initialTab,
      ),
    ),
  );
  await tester.pumpAndSettle();
  expect(
    tester.widget<TabBarView>(find.byType(TabBarView)).controller!.index,
    initialTab.index,
  );
}

Future<void> _selectStatus(WidgetTester tester) async {
  final tabs = tester.widget<ConnectedTabs>(find.byType(ConnectedTabs));
  await tester.tap(
    find.descendant(
      of: find.byType(ConnectedTabs),
      matching: find.text(tabs.labels[VideoDetailsTab.status.index]),
    ),
  );
  await tester.pumpAndSettle();
  expect(
    tester.widget<TabBarView>(find.byType(TabBarView)).controller!.index,
    VideoDetailsTab.status.index,
  );
}

void main() {
  setUp(() => TvMode.setEnabledForTesting(true));
  tearDown(() => TvMode.setEnabledForTesting(false));

  testWidgets(
      'remote sheet shares row focus, scrolls to end and exits without native calls',
      (tester) async {
    final playback = _FakePlaybackController(Future.value(_diagnostics));
    final player = _FakePlayerController(playback);
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => Scaffold(
                body: TextButton(
                    onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                            builder: (_) => VideoDetailsSheet(
                                playerController: player,
                                initialTab: VideoDetailsTab.remote))),
                    child: const Text('Open remote help'))))));
    await tester.tap(find.text('Open remote help'));
    await tester.pumpAndSettle();
    expect(find.byType(TvRemoteHelp), findsOneWidget);
    final first = find.byKey(const ValueKey('tv-remote-help-item-1-0'));
    Focus.of(tester.element(
            find.descendant(of: first, matching: find.byType(ListTile))))
        .requestFocus();
    await tester.pumpAndSettle();
    for (var i = 0; i < 9; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
    }
    final list = find.byKey(const PageStorageKey('video-details-remote-help'));
    final scroll = tester.state<ScrollableState>(
        find.descendant(of: list, matching: find.byType(Scrollable)).first);
    expect(scroll.position.pixels, greaterThan(200));
    expect(playback.diagnosticsReadCount, 0);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(VideoDetailsSheet), findsNothing);
    expect(find.text('Open remote help'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final initialTab in [VideoDetailsTab.remote, VideoDetailsTab.logs]) {
    testWidgets('TV ${initialTab.name} starts without reading diagnostics',
        (tester) async {
      final playback = _FakePlaybackController(Future.value(_diagnostics));
      final player = _FakePlayerController(playback);

      await _pumpSheet(tester, player, initialTab: initialTab);
      await tester.pump(const Duration(seconds: 1));

      expect(
        playback.diagnosticsReadCount,
        0,
        reason: 'Opening help or logs must not query the native player.',
      );
    });

    testWidgets(
        'TV ${initialTab.name} to status reads once and shows the result',
        (tester) async {
      final result = Completer<PlayerDiagnosticsSnapshot>();
      final playback = _FakePlaybackController(result.future);
      final player = _FakePlayerController(playback);

      await _pumpSheet(tester, player, initialTab: initialTab);
      expect(playback.diagnosticsReadCount, 0);

      await _selectStatus(tester);
      expect(
        playback.diagnosticsReadCount,
        1,
        reason: 'The tab animation must not start duplicate pending reads.',
      );
      expect(find.text(_diagnostics.outputSummary), findsNothing);

      result.complete(_diagnostics);
      await tester.pumpAndSettle();

      expect(find.text(_diagnostics.outputSummary), findsOneWidget);
      expect(find.text(_diagnostics.decodeRouteSummary), findsOneWidget);
      expect(playback.diagnosticsReadCount, 1);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('TV status starts with one diagnostic read and shows the result',
      (tester) async {
    final result = Completer<PlayerDiagnosticsSnapshot>();
    final playback = _FakePlaybackController(result.future);
    final player = _FakePlayerController(playback);

    await _pumpSheet(tester, player, initialTab: VideoDetailsTab.status);
    expect(playback.diagnosticsReadCount, 1);
    expect(find.text(_diagnostics.outputSummary), findsNothing);

    result.complete(_diagnostics);
    await tester.pumpAndSettle();

    expect(find.text(_diagnostics.outputSummary), findsOneWidget);
    expect(find.text(_diagnostics.decodeRouteSummary), findsOneWidget);
    expect(playback.diagnosticsReadCount, 1);
    expect(tester.takeException(), isNull);
  });
}
