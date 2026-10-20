import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import '../tools/qa/source_batch/media_root_observer.dart';

class CountingBytes extends ListBase<int> {
  int reads = 0;
  @override
  int get length => 2 * 1024 * 1024;
  @override
  set length(int value) => throw UnsupportedError('read only');
  @override
  int operator [](int index) {
    reads++;
    return 120;
  }

  @override
  void operator []=(int index, int value) =>
      throw UnsupportedError('read only');
}

class Headers implements HttpHeaders {
  final values = <String, Object>{};
  @override
  ContentType get contentType => ContentType.text;
  @override
  String? value(String name) => null;
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {
    values[name] = value;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('unused header API');
}

class Response extends Stream<List<int>> implements HttpClientResponse {
  Response(this.body);
  final Stream<List<int>> body;
  @override
  int get statusCode => 200;
  @override
  HttpHeaders get headers => Headers();
  @override
  StreamSubscription<List<int>> listen(void Function(List<int>)? onData,
          {Function? onError, void Function()? onDone, bool? cancelOnError}) =>
      body.listen(onData,
          onError: onError, onDone: onDone, cancelOnError: cancelOnError);
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('unused response API');
}

class Request implements HttpClientRequest {
  Request(this.response);
  final HttpClientResponse response;
  @override
  bool followRedirects = false;
  @override
  HttpHeaders headers = Headers();
  @override
  Future<HttpClientResponse> close() async => response;
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('unused request API');
}

class Client implements HttpClient {
  Client(this.response);
  final HttpClientResponse response;
  int requests = 0, closes = 0;
  @override
  Duration? connectionTimeout;
  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    requests++;
    return Request(response);
  }

  @override
  void close({bool force = false}) {
    closes++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('unused client API');
}

Future<Map<String, Object?>> inspect(Client client, Duration budget) =>
    HttpOverrides.runZoned(
        () => observeMediaRoot(
            enabled: true,
            debug: true,
            packageName: 'com.znbsf.kazumi.fluttertv.parserqa',
            mediaUrl: 'https://example.invalid/root',
            headers: {'User-Agent': 'SYNTHETIC'},
            isCancelled: () => false,
            budget: budget),
        createHttpClient: (_) => client);

void main() {
  test('oversized chunk should not copy beyond the 64KiB observation bound',
      () async {
    final bytes = CountingBytes();
    final client = Client(Response(Stream.value(bytes)));
    final result = await inspect(client, const Duration(seconds: 1));
    expect(client.requests, 1);
    expect((result['observations'] as List).single['buffered_bytes'], 65536);
    expect(bytes.reads, lessThanOrEqualTo(65536));
  });
  test(
      'stalled stream retirement must remain within the total observation budget',
      () async {
    final release = Completer<void>();
    late StreamController<List<int>> controller;
    controller = StreamController<List<int>>(
        onListen: () {
          controller.add(List.filled(65536, 120));
        },
        onCancel: () => release.future);
    final client = Client(Response(controller.stream));
    final watch = Stopwatch()..start();
    try {
      final result = await inspect(client, const Duration(milliseconds: 40));
      expect(client.requests, 1);
      expect(result['outcome'], 'cleanup_unconfirmed');
      expect((result['observations'] as List).single['status'], 200);
      expect(result['cleanup_unconfirmed'], true);
      expect(client.closes, greaterThanOrEqualTo(1));
      expect(watch.elapsedMilliseconds, lessThan(200));
    } finally {
      release.complete();
      await controller.close();
    }
  });
}
