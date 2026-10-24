import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import '../tools/qa/source_batch/launch_probe.dart';

class TrapAdapter implements HttpClientAdapter {
  bool called = false;
  @override
  Future<ResponseBody> fetch(
      RequestOptions o, Stream<Uint8List>? s, Future<void>? c) async {
    called = true;
    throw StateError('transport_must_not_run');
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('qa-launch-test');
  final events = <String>[];
  setUp(() {
    events.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (c) async {
      events.add(c.method == 'launchProbeStage'
          ? (c.arguments as Map)['stage'] as String
          : c.method);
      return null;
    });
  });
  tearDown(() => TestDefaultBinaryMessengerBinding
      .instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, null));
  test('offline mode is compile-time opt-in and input cannot carry source work',
      () {
    expect(qaLaunchOnlyBuild, false);
    final c = <String, dynamic>{
      'id': qaLaunchId,
      'group': 'offline-launch',
      'engine': 'app',
      'launch_only': true,
      'repeat': 0,
      'user_agent': 'QA',
      'launch_attempt_key': 'a' * 20
    };
    expect(validQaLaunchConfig(c), true);
    expect(qaLaunchConfigAllowed(c, offlineBuild: false), false);
    expect(
        qaLaunchConfigAllowed({'id': qaLaunchId}, offlineBuild: false), false);
    expect(
        qaLaunchConfigAllowed({'id': 'ordinary', 'engine': 'app'},
            offlineBuild: false),
        true);
    for (final key in [
      'rule',
      'rule_file',
      'keyword',
      'url',
      'fallback',
      'observer',
      'selection_only'
    ]) {
      expect(validQaLaunchConfig({...c, key: 'PRIVATE_SENTINEL'}), false);
    }
    for (final delta in [
      {'launch_only': false},
      {'engine': 'gecko'},
      {'id': 'another'},
      {'repeat': 1},
      {'launch_attempt_key': 'https://invalid.test/secret'},
      {'user_agent': 4}
    ]) {
      expect(validQaLaunchConfig({...c, ...delta}), false);
    }
  });
  test('HttpClient creation is denied before any socket operation', () async {
    await HttpOverrides.runZoned(() async {
      expect(() => HttpClient(), throwsStateError);
    }, createHttpClient: QaNoNetworkOverrides().createHttpClient);
  });
  test('Dio guard rejects before a supplied transport can run', () async {
    final adapter = TrapAdapter();
    final dio = Dio()..httpClientAdapter = adapter;
    dio.interceptors.add(QaDioNetworkDeny());
    await expectLater(
        dio.get<void>('https://invalid.test/PRIVATE_SENTINEL'),
        throwsA(isA<DioException>()
            .having((e) => e.type, 'type', DioExceptionType.cancel)));
    expect(adapter.called, false);
    dio.close();
  });
  test('checkpoint awaits preserve operation order and stop at failure',
      () async {
    const probe = QaLaunchProbe(channel);
    await probe.step('identity', () async {
      events.add('identity_operation');
    });
    await expectLater(
        probe.step('config', () {
          events.add('config_operation');
          throw StateError('PRIVATE_SENTINEL');
        }),
        throwsStateError);
    expect(events, [
      'dart_identity_enter',
      'identity_operation',
      'dart_identity_exit',
      'dart_config_enter',
      'config_operation'
    ]);
  });
  test('failure exports only exception class, without message or stack',
      () async {
    Object? args;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (c) async {
      args = c.arguments;
      return null;
    });
    await const QaLaunchProbe(channel).failure(StateError('PRIVATE_SENTINEL'));
    expect(args, {'stage': 'dart_failure', 'error_type': 'StateError'});
  });
  testWidgets('local first frame publishes once without a case builder',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: QaLaunchOnlyPage(probe: QaLaunchProbe(channel))));
    await tester.pump();
    expect(find.text('Offline QA startup ready'), findsOneWidget);
    expect(events, ['dart_first_frame', 'launchProbeComplete']);
    await tester.pump();
    expect(events.length, 2);
  });
}
