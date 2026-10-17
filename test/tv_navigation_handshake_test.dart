import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:kazumi/bean/widget/tv_app_shell.dart';
import 'package:kazumi/services/platform/tv_mode.dart';
import 'package:kazumi/services/storage/storage.dart';

class _Paths extends PathProviderPlatform {
  _Paths(this.path);
  final String path;
  @override
  Future<String?> getApplicationSupportPath() async => path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.predidit.kazumi/tv_navigation');
  late Directory directory;
  late PathProviderPlatform previousPaths;
  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('navigation_handshake_');
    previousPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _Paths(directory.path);
    Hive.init(directory.path);
    await GStorage.init();
  });
  tearDownAll(() async {
    await Hive.close();
    PathProviderPlatform.instance = previousPaths;
    await directory.delete(recursive: true);
  });
  setUp(() => TvMode.setEnabledForTesting(true));
  tearDown(() {
    TvMode.setEnabledForTesting(false);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });
  Future<void> ready(WidgetTester tester) async {
    final done = Completer<void>();
    tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        channel.name,
        const StandardMethodCodec().encodeMethodCall(const MethodCall('ready')),
        (_) => done.complete());
    await tester.pump();
    await done.future;
  }

  Widget shell() => MaterialApp(
      home: TvAppShell(
          child: Scaffold(
              body: TextButton(
                  autofocus: true,
                  onPressed: () {},
                  child: const Text('Ready')))));

  testWidgets('early missing native handler recovers once ready is received',
      (tester) async {
    final calls = <bool>[];
    var registered = false;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
        (call) async {
      if (!registered) throw MissingPluginException();
      calls.add(call.arguments as bool);
      return null;
    });
    await tester.pumpWidget(shell());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(calls, isEmpty);
    registered = true;
    await ready(tester);
    expect(calls, [true]);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(calls, [true, false]);
  });

  testWidgets('ready after shell disposal cannot reactivate navigation',
      (tester) async {
    final calls = <bool>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
        (call) async {
      calls.add(call.arguments as bool);
      return null;
    });
    await tester.pumpWidget(shell());
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(calls, [true, false]);
    await ready(tester);
    expect(calls, [true, false]);
    expect(tester.takeException(), isNull);
  });
}
