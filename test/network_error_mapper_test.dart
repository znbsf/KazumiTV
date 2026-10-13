import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/request/core/network_error_mapper.dart';
import 'package:kazumi/request/core/network_exception.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dev.fluttercommunity.plus/connectivity');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));
  DioException error([DioExceptionType type = DioExceptionType.unknown]) =>
      DioException(
          requestOptions: RequestOptions(path: 'https://example.test'),
          type: type,
          error: 'original source failure');

  test('unknown error returns original failure when connectivity lookup hangs',
      () async {
    final pending = Completer<List<String>>();
    messenger.setMockMethodCallHandler(channel, (_) => pending.future);
    final original = error();
    try {
      final result = await NetworkErrorMapper.mapException(original)
          .timeout(const Duration(milliseconds: 1500));
      expect(result.type, NetworkExceptionType.unknown);
      expect(result.rawError, same(original));
      expect(result.message, '网络异常');
    } finally {
      pending.complete(['wifi']);
    }
  });
  test('connectivity lookup failure never replaces original network failure',
      () async {
    messenger.setMockMethodCallHandler(channel, (_) async {
      throw PlatformException(code: 'unavailable');
    });
    final original = error();
    final result = await NetworkErrorMapper.mapException(original);
    expect(result.rawError, same(original));
    expect(result.type, NetworkExceptionType.unknown);
    expect(result.message, '网络异常');
  });
  test('available connectivity label survives, cancellation never queries it',
      () async {
    var calls = 0;
    messenger.setMockMethodCallHandler(channel, (_) async {
      calls++;
      return ['wifi'];
    });
    final result = await NetworkErrorMapper.mapException(error());
    expect(result.message, contains('wifi'));
    final cancelled =
        await NetworkErrorMapper.mapException(error(DioExceptionType.cancel));
    expect(cancelled.type, NetworkExceptionType.cancel);
    expect(calls, 1);
  });
}
