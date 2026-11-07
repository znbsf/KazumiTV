import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:hive_ce/hive.dart';
import 'package:kazumi/services/network/proxy_aware_image_cache_manager.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:logger/logger.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  late PathProviderPlatform paths;
  late HttpServer server;
  late _Clients clients;
  late Set<int> ports;
  late String url;
  late Future<void> Function(HttpRequest) serve;

  setUpAll(() async {
    Logger.level = Level.off;
    temp = await Directory.systemTemp.createTemp('image_client_pool_');
    paths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _Paths(temp.path);
    Hive.init(temp.path);
    await GStorage.init();
  });
  setUp(() async {
    await GStorage.putSetting(SettingsKeys.proxyEnable, false);
    await GStorage.putSetting(SettingsKeys.proxyUrl, '');
    await GStorage.putSetting(SettingsKeys.enableBangumiProxy, false);
    clients = _Clients();
    ports = {};
    serve = (request) async {
      request.response.headers.contentType = ContentType('image', 'png');
      request.response.write('image');
      await request.response.close();
    };
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    url = 'http://127.0.0.1:${server.port}/image';
    server.listen((request) async {
      ports.add(request.connectionInfo!.remotePort);
      await request.drain<void>();
      await serve(request);
    });
  });
  tearDown(() async {
    for (final client in clients.created) {
      client.close(force: true);
    }
    await server.close(force: true);
  });
  tearDownAll(() async {
    await Hive.close();
    PathProviderPlatform.instance = paths;
    expect(temp.uri.pathSegments.where((s) => s.isNotEmpty).last,
        startsWith('image_client_pool_'));
    await temp.delete(recursive: true);
  });

  Future<void> realHttp(Future<void> Function() body) =>
      HttpOverrides.runZoned(body, createHttpClient: clients.createHttpClient)
          .timeout(const Duration(seconds: 5));

  const stallTimeout = Duration(milliseconds: 250);
  const deadline = Duration(seconds: 2);
  final stalled = isA<TimeoutException>();

  // Keep each successful response open until all six have arrived. A single
  // leaked slot would prevent this batch from completing, even with TCP reuse.
  Future<void> expectAllSlotsLoad(FileService service) async {
    final release = Completer<void>();
    var arrived = 0;
    serve = (request) async {
      request.response.bufferOutput = false;
      request.response.write('image');
      await request.response.flush();
      if (++arrived == 6) release.complete();
      await release.future;
      await request.response.close();
    };
    await Future.wait(List.generate(6, (i) async {
      final response = await service.get('$url?later=$i');
      expect(await response.content.expand((chunk) => chunk).toList(),
          'image'.codeUnits);
    })).timeout(deadline);
    expect(arrived, 6);
    expect(clients.created, hasLength(1));
    expect(clients.created.single.maxConnectionsPerHost, 6);
  }

  test('stalled headers abort all six requests and release all pool slots',
      () async {
    await realHttp(() async {
      var accepted = 0;
      serve = (_) async {
        accepted++;
      };
      final service = ProxyAwareImageCacheManager.createFileServiceForTesting(
          stallTimeout: stallTimeout);
      await Future.wait(List.generate(
              6,
              (i) => expectLater(
                  service.get('$url?stalled=$i'), throwsA(stalled))))
          .timeout(deadline);
      expect(accepted, 6);
      await expectAllSlotsLoad(service);
    });
  }, timeout: const Timeout(Duration(seconds: 6)));

  test('stalled partial body errors and releases its pool slot', () async {
    await realHttp(() async {
      serve = (request) async {
        request.response.bufferOutput = false;
        request.response.write('first');
        await request.response.flush();
      };
      final service = ProxyAwareImageCacheManager.createFileServiceForTesting(
          stallTimeout: stallTimeout);
      final response = await service.get(url);
      final chunks = <int>[];
      final done = response.content.map((chunk) {
        chunks.addAll(chunk);
      });
      await expectLater(done.drain<void>(), throwsA(stalled)).timeout(deadline);
      expect(chunks, 'first'.codeUnits);
      await expectAllSlotsLoad(service);
    });
  }, timeout: const Timeout(Duration(seconds: 6)));

  test('steady chunks reset the stall timer beyond the total timeout',
      () async {
    await realHttp(() async {
      serve = (request) async {
        request.response.bufferOutput = false;
        for (var i = 0; i < 6; i++) {
          request.response.write('chunk');
          await request.response.flush();
          if (i < 5) {
            await Future<void>.delayed(const Duration(milliseconds: 75));
          }
        }
        await request.response.close();
      };
      final service = ProxyAwareImageCacheManager.createFileServiceForTesting(
          stallTimeout: stallTimeout);
      final elapsed = Stopwatch()..start();
      final response = await service.get(url);
      expect(await response.content.expand((chunk) => chunk).toList(),
          List.generate(6, (_) => 'chunk').join().codeUnits);
      expect(elapsed.elapsed, greaterThan(stallTimeout));
    });
  }, timeout: const Timeout(Duration(seconds: 6)));

  test('consumer pause longer than the stall timeout does not abort', () async {
    await realHttp(() async {
      final release = Completer<void>();
      serve = (request) async {
        request.response.bufferOutput = false;
        request.response.write('first');
        await request.response.flush();
        await release.future;
        request.response.write('last');
        await request.response.close();
      };
      final service = ProxyAwareImageCacheManager.createFileServiceForTesting(
          stallTimeout: stallTimeout);
      final response = await service.get(url);
      final paused = Completer<void>();
      final done = Completer<void>();
      final bytes = <int>[];
      late StreamSubscription<List<int>> subscription;
      subscription = response.content.listen((chunk) {
        bytes.addAll(chunk);
        if (!paused.isCompleted) {
          subscription.pause();
          paused.complete();
        }
      }, onError: done.completeError, onDone: done.complete);
      await paused.future.timeout(deadline);
      await Future<void>.delayed(const Duration(milliseconds: 600));
      // The server sends nothing during the entire consumer pause.
      subscription.resume();
      release.complete();
      await done.future.timeout(deadline);
      expect(bytes, 'firstlast'.codeUnits);
      await expectAllSlotsLoad(service);
    });
  }, timeout: const Timeout(Duration(seconds: 6)));

  test('cancelled midway then stalled discard completes and releases its slot',
      () async {
    await realHttp(() async {
      serve = (request) async {
        request.response.bufferOutput = false;
        request.response.write('first');
        await request.response.flush();
      };
      final service = ProxyAwareImageCacheManager.createFileServiceForTesting(
          stallTimeout: stallTimeout);
      final response = await service.get(url);
      final firstChunk = Completer<void>();
      final subscription = response.content.listen((_) {
        if (!firstChunk.isCompleted) firstChunk.complete();
      });
      await firstChunk.future.timeout(deadline);
      subscription.pause();
      await subscription.cancel().timeout(deadline);
      await expectAllSlotsLoad(service);
    });
  }, timeout: const Timeout(Duration(seconds: 6)));

  for (final status in [HttpStatus.notFound, HttpStatus.serviceUnavailable]) {
    test('stalled $status drain aborts and releases its pool slot', () async {
      await realHttp(() async {
        serve = (request) async {
          request.response.bufferOutput = false;
          request.response.statusCode = status;
          request.response.write('first');
          await request.response.flush();
        };
        final service = ProxyAwareImageCacheManager.createFileServiceForTesting(
            stallTimeout: stallTimeout);
        await expectLater(service.get(url), throwsA(stalled)).timeout(deadline);
        await expectAllSlotsLoad(service);
      });
    }, timeout: const Timeout(Duration(seconds: 6)));
  }

  test('sequential images reuse one TCP connection and the bounded client',
      () async {
    await realHttp(() async {
      final service = ProxyAwareImageCacheManager.createFileServiceForTesting();
      for (var i = 0; i < 12; i++) {
        final response = await service.get('$url?image=$i');
        expect(await response.content.expand((bytes) => bytes).toList(),
            'image'.codeUnits);
        expect(response.fileExtension, '.png');
      }
      expect(ports, hasLength(1));
      expect(clients.created, hasLength(1));
      expect(clients.created.single.maxConnectionsPerHost, 6);
      expect(clients.created.single.connectionTimeout,
          const Duration(seconds: 12));
    });
  });

  test(
      'parsed proxy and enabled state select client; equivalent text reuses it',
      () async {
    await realHttp(() async {
      final service = ProxyAwareImageCacheManager.createFileServiceForTesting();
      Future<void> fetch() async =>
          (await service.get(url)).content.drain<void>();
      await fetch();
      // Disabled proxy text is not effective and must not rebuild the pool.
      await GStorage.putSetting(
          SettingsKeys.proxyUrl, '127.0.0.1:${server.port}');
      await fetch();
      expect(clients.created, hasLength(1));
      await GStorage.putSetting(SettingsKeys.proxyEnable, true);
      await fetch();
      expect(clients.created, hasLength(2));
      await GStorage.putSetting(
          SettingsKeys.proxyUrl, 'http://127.0.0.1:${server.port}');
      await fetch();
      expect(clients.created, hasLength(2));
      // A second loopback server is a distinct effective manual proxy.
      final proxy = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => proxy.close(force: true));
      var proxyCalls = 0;
      proxy.listen((request) async {
        proxyCalls++;
        await request.drain<void>();
        request.response.write('proxy image');
        await request.response.close();
      });
      await GStorage.putSetting(
          SettingsKeys.proxyUrl, '127.0.0.1:${proxy.port}');
      await fetch();
      expect(proxyCalls, 1);
      expect(clients.created, hasLength(3));
      await GStorage.putSetting(SettingsKeys.proxyEnable, false);
      await fetch();
      expect(clients.created, hasLength(4));
    });
  });

  test('enabled state rebuilds even when both parsed proxies are null',
      () async {
    await realHttp(() async {
      final service = ProxyAwareImageCacheManager.createFileServiceForTesting();
      await (await service.get(url)).content.drain<void>();
      await GStorage.putSetting(SettingsKeys.proxyEnable, true);
      await (await service.get(url)).content.drain<void>();
      expect(clients.created, hasLength(2));
    });
  });

  test('retiring client for proxy change lets an in-flight image finish',
      () async {
    await realHttp(() async {
      final release = Completer<void>();
      serve = (request) async {
        request.response.write('first');
        await request.response.flush();
        if (request.uri.query == 'held') await release.future;
        request.response.write('last');
        await request.response.close();
      };
      final service = ProxyAwareImageCacheManager.createFileServiceForTesting();
      final first = await service.get('$url?held');
      await GStorage.putSetting(SettingsKeys.proxyEnable, true);
      final second = await service.get(url);
      await second.content.drain<void>();
      expect(clients.created, hasLength(2));
      release.complete();
      expect(await first.content.expand((chunk) => chunk).toList(),
          'firstlast'.codeUnits);
    });
  });

  test('unread 404/503/304 bodies release slots and preserve the pool',
      () async {
    await realHttp(() async {
      serve = (request) async {
        final status = int.parse(request.uri.query);
        request.response.statusCode = status;
        if (status != HttpStatus.notModified) {
          request.response.add(List.filled(32 * 1024, 1));
        }
        await request.response.close();
      };
      final service = ProxyAwareImageCacheManager.createFileServiceForTesting();
      for (var i = 0; i < 24; i++) {
        final status = [404, 503, 304][i % 3];
        final response = await service.get('$url?$status');
        expect(response.statusCode, status);
        // Like WebHelper, deliberately never read response.content.
      }
      expect(clients.created, hasLength(1));
      expect(ports.length, lessThanOrEqualTo(6));
    });
  });

  test('abandoning content midway drains the body and reuses its TCP slot',
      () async {
    await realHttp(() async {
      var release = Completer<void>();
      serve = (request) async {
        request.response.bufferOutput = false;
        request.response.add(List.filled(8192, 1));
        await request.response.flush();
        await release.future;
        request.response.add(List.filled(32 * 1024, 2));
        await request.response.close();
      };
      final service = ProxyAwareImageCacheManager.createFileServiceForTesting();
      for (var i = 0; i < 18; i++) {
        release = Completer<void>();
        final response = await service.get(url);
        final firstChunk = Completer<void>();
        final subscription = response.content.listen((_) {
          if (!firstChunk.isCompleted) firstChunk.complete();
        });
        await firstChunk.future;
        // Exercise cancellation while the source is paused too.
        subscription.pause();
        final cancelled = subscription.cancel();
        release.complete();
        await cancelled;
      }
      expect(clients.created, hasLength(1));
      expect(ports, hasLength(1));
    });
  });
}

class _Clients extends HttpOverrides {
  final created = <HttpClient>[];
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    created.add(client);
    return client;
  }
}

class _Paths extends PathProviderPlatform {
  _Paths(this.path);
  final String path;
  @override
  Future<String?> getApplicationSupportPath() async => path;
}
