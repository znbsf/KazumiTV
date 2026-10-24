// Explicit QA-only offline startup observation; never imported by product main.
import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const qaLaunchOnlyBuild = bool.fromEnvironment('KAZUMI_QA_LAUNCH_ONLY');
const qaLaunchId = 'qa-offline-launch-only-v1';

bool validQaLaunchConfig(Map<String, dynamic> config) {
  const keys = {
    'id',
    'group',
    'engine',
    'launch_only',
    'repeat',
    'user_agent',
    'launch_attempt_key'
  };
  return config.keys.every(keys.contains) &&
      config['id'] == qaLaunchId &&
      config['group'] == 'offline-launch' &&
      config['engine'] == 'app' &&
      config['launch_only'] == true &&
      config['repeat'] == 0 &&
      config['user_agent'] is String &&
      (config['user_agent'] as String).length <= 256 &&
      config['launch_attempt_key'] is String &&
      RegExp(r'^[a-f0-9]{20}$')
          .hasMatch(config['launch_attempt_key'] as String);
}

bool qaLaunchConfigAllowed(Map<String, dynamic> config,
        {required bool offlineBuild}) =>
    offlineBuild
        ? validQaLaunchConfig(config)
        : !config.containsKey('launch_only') && config['id'] != qaLaunchId;

class QaNoNetworkOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      throw StateError('qa_offline_network_denied');
}

class QaDioNetworkDeny extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    handler.reject(DioException(
        requestOptions: options,
        type: DioExceptionType.cancel,
        error: StateError('qa_offline_network_denied')));
  }
}

class QaLaunchProbe {
  const QaLaunchProbe([this.channel = const MethodChannel('kazumi/parser_qa')]);
  final MethodChannel channel;
  Future<void> mark(String stage) =>
      channel.invokeMethod<void>('launchProbeStage', {'stage': stage});
  Future<T> step<T>(String stage, FutureOr<T> Function() operation) async {
    await mark('dart_${stage}_enter');
    final value = await operation();
    await mark('dart_${stage}_exit');
    return value;
  }

  Future<void> failure(Object error) async {
    try {
      await channel.invokeMethod<void>('launchProbeStage', {
        'stage': 'dart_failure',
        'error_type': error.runtimeType.toString()
      });
    } catch (_) {/* Never stringify failed channel calls or their arguments. */}
  }
}

Future<T> qaBootstrapStep<T>(
        QaLaunchProbe? probe, String stage, FutureOr<T> Function() operation) =>
    probe == null ? Future<T>.sync(operation) : probe.step(stage, operation);

class QaLaunchOnlyPage extends StatefulWidget {
  const QaLaunchOnlyPage({super.key, required this.probe});
  final QaLaunchProbe probe;
  @override
  State<QaLaunchOnlyPage> createState() => _QaLaunchOnlyPageState();
}

class _QaLaunchOnlyPageState extends State<QaLaunchOnlyPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        await widget.probe.mark('dart_first_frame');
        await widget.probe.channel.invokeMethod<void>('launchProbeComplete');
      } catch (error) {
        await widget.probe.failure(error);
        rethrow;
      }
    });
  }

  @override
  Widget build(BuildContext context) => const Scaffold(
      backgroundColor: Colors.black,
      body: Center(
          child: Text('Offline QA startup ready',
              style: TextStyle(color: Colors.white))));
}
