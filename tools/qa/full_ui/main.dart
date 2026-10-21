// Independent parserQa/debug full UI. Ordinary lib/main.dart never imports this.
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show appFlavor, MissingPluginException;
// ignore: depend_on_referenced_packages
import 'package:package_info_plus/package_info_plus.dart';
import 'package:kazumi/main.dart' as app;
import 'package:kazumi/pages/video/video_controller.dart';
import 'package:kazumi/pages/video/video_module.dart';
import 'package:kazumi/services/platform/tv_mode.dart';
import 'package:kazumi/services/player/source_switch.dart';
import 'package:kazumi/services/video_source/resolved_source_cache.dart';

import '../source_batch/gecko_controller.dart' show qaChannel;
import 'video_source_binding.dart';

bool qaFullUiProfileAllowed({
  required bool debug,
  required bool android,
  required bool dartEnabled,
  required bool dartOffline,
  required String? flavor,
  required String packageName,
  required Map<Object?, Object?> native,
}) =>
    debug &&
    android &&
    dartEnabled &&
    !dartOffline &&
    flavor == 'parserQa' &&
    packageName == 'com.znbsf.kazumi.fluttertv.parserqa' &&
    native['package'] == packageName &&
    native['activity'] == 'com.example.kazumi.ParserQaActivity' &&
    native['debug'] == true &&
    native['full_ui'] == true &&
    native['tv'] == true &&
    native['offline'] == false;

/// One capability read, or a bounded native-ready notification if a warmed
/// audio-service engine starts Dart before its Activity channel is attached.
/// This listener exists only during bootstrap, before any Gecko controller.
Future<Map<Object?, Object?>> readQaFullUiCapability({
  Duration timeout = const Duration(seconds: 2),
}) async {
  final ready = Completer<Map<Object?, Object?>>();
  var waiting = true;
  qaChannel.setMethodCallHandler((call) async {
    if (waiting &&
        !ready.isCompleted &&
        call.method == 'qaUiReady' &&
        call.arguments is Map) {
      ready.complete(Map<Object?, Object?>.from(call.arguments as Map));
    }
  });
  Future<void> readOnce() async {
    try {
      final value =
          await qaChannel.invokeMapMethod<Object?, Object?>('qaUiCapability');
      if (waiting && !ready.isCompleted && value != null) ready.complete(value);
    } on MissingPluginException {
      // Wait only for the native attachment notification, never poll or opt in.
    } catch (error) {
      if (waiting && !ready.isCompleted) ready.completeError(error);
    }
  }

  unawaited(readOnce());
  try {
    return await ready.future.timeout(timeout);
  } finally {
    waiting = false;
    qaChannel.setMethodCallHandler(null);
  }
}

/// Start only the eligible native runtime after the full profile handshake.
/// No parser lease, page, headers or playback budget is created by this call.
/// Unsupported/slow warmup must never prevent the ordinary UI from starting.
Future<void> requestQaFullUiRuntimeWarmup({
  required bool profileAllowed,
  Duration timeout = const Duration(seconds: 2),
}) async {
  if (!profileAllowed) return;
  try {
    await qaChannel.invokeMethod<bool>('qaWarmRuntime').timeout(timeout);
  } catch (_) {
    // Native startup remains optional; the existing bounded resolver still runs.
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  var allowed = false;
  try {
    if (kDebugMode &&
        Platform.isAndroid &&
        const bool.fromEnvironment('KAZUMI_QA_FULL_UI') &&
        !const bool.fromEnvironment('KAZUMI_QA_LAUNCH_ONLY')) {
      final package =
          await PackageInfo.fromPlatform().timeout(const Duration(seconds: 2));
      final native = await readQaFullUiCapability();
      allowed = qaFullUiProfileAllowed(
        debug: kDebugMode,
        android: Platform.isAndroid,
        dartEnabled: const bool.fromEnvironment('KAZUMI_QA_FULL_UI'),
        dartOffline: const bool.fromEnvironment('KAZUMI_QA_LAUNCH_ONLY'),
        flavor: appFlavor,
        packageName: package.packageName,
        native: native,
      );
    }
  } catch (_) {
    // No native Activity/incorrect flavor/headless engine cannot opt in.
  }
  if (!allowed) {
    runApp(const MaterialApp(
      home: Scaffold(body: Center(child: Text('QA 完整界面未启用：构建身份不匹配'))),
    ));
    return;
  }
  unawaited(requestQaFullUiRuntimeWarmup(profileAllowed: allowed));
  final retirement = QaUiRetirementGate();
  // ignore: invalid_use_of_visible_for_testing_member
  debugVideoPageControllerBuilder = (history, downloads, manager) {
    final resolver = QaUiVideoSourceBinding.production(gate: retirement);
    return VideoPageController(
      history,
      downloads,
      manager,
      videoSourceService: resolver,
      resolveVideoSourceWithHeaders: resolver.resolveWithHeaders,
      createSourceSwitchResolver: () {
        // A picker gets its own sessions/cancel/dispose, but cannot overlap a
        // route's active or unconfirmed parser retirement.
        final selected = QaUiVideoSourceBinding.production(gate: retirement);
        return SourceSwitchResolver(selected,
            resolveWithHeaders: selected.resolveWithHeaders);
      },
      videoSourceLog: resolver.onLog,
      resolvedSourceCache: ResolvedSourceCache(),
    );
  };
  // initialize() in app.main must retain this handshake-bound debug identity.
  // ignore: invalid_use_of_visible_for_testing_member
  TvMode.setDebugParserQaFullUi(true);
  app.main();
}
