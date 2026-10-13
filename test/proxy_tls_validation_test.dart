import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kazumi/request/core/dio_factory.dart';
import 'package:kazumi/request/core/network_config.dart';
import 'package:kazumi/services/network/proxy_aware_image_cache_manager.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _Paths extends PathProviderPlatform {
  _Paths(this.path);
  final String path;
  @override
  Future<String?> getApplicationSupportPath() async => path;
  @override
  Future<String?> getTemporaryPath() async => path;
}

// Test-only trust anchor, scoped to a zone. No OS/app trust-store modification,
// certificate callback, or hostname bypass. The real clients perform TLS.
class _FixtureTrust extends HttpOverrides {
  _FixtureTrust({bool trustFixture = true}) {
    context = SecurityContext(withTrustedRoots: false);
    if (trustFixture) {
      context.setTrustedCertificates('test/fixtures/proxy_tls/test-ca.pem');
    }
  }
  late final SecurityContext context;
  @override
  HttpClient createHttpClient(SecurityContext? _) =>
      super.createHttpClient(context);
}

class _Origin {
  _Origin(this.server) {
    server.listen((request) async {
      requests.add((request.uri.toString(), request.headers.value('x-probe')));
      request.response.headers.contentType = ContentType.text;
      request.response.headers.set('cache-control', 'max-age=60');
      request.response.write('verified response');
      await request.response.close();
    }, onError: (Object _) {
      // Expected handshake rejection is asserted on the requesting client.
    });
  }
  final HttpServer server;
  final requests = <(String, String?)>[];
  String get url => 'https://127.0.0.1:${server.port}/image?case=tls';
  static Future<_Origin> start(String certificate) async {
    final context = SecurityContext()
      ..useCertificateChain('test/fixtures/proxy_tls/$certificate.pem')
      ..usePrivateKey('test/fixtures/proxy_tls/server-test-only.key');
    return _Origin(
        await HttpServer.bindSecure(InternetAddress.loopbackIPv4, 0, context));
  }

  Future<void> close() => server.close(force: true);
}

class _ConnectProxy {
  _ConnectProxy(this.server, this.allowedPorts) {
    server.listen(_accept);
  }
  final ServerSocket server;
  final Set<int> allowedPorts;
  final sockets = <Socket>[];
  final targets = <String>[];
  int get port => server.port;
  static Future<_ConnectProxy> start(Set<int> ports) async => _ConnectProxy(
      await ServerSocket.bind(InternetAddress.loopbackIPv4, 0), ports);

  void _accept(Socket downstream) {
    sockets.add(downstream);
    Socket? upstream;
    var headers = <int>[];
    downstream.listen((data) async {
      if (upstream != null) {
        upstream!.add(data);
        return;
      }
      headers.addAll(data);
      final text = ascii.decode(headers, allowInvalid: true);
      if (!text.contains('\r\n\r\n')) return;
      final match = RegExp(r'^CONNECT (127\.0\.0\.1):(\d+) HTTP/1\.[01]\r\n')
          .firstMatch(text);
      if (match == null || !allowedPorts.contains(int.parse(match.group(2)!))) {
        downstream.destroy();
        return;
      }
      targets.add('${match.group(1)}:${match.group(2)}');
      upstream = await Socket.connect(
          InternetAddress.loopbackIPv4, int.parse(match.group(2)!));
      sockets.add(upstream!);
      upstream!.listen(downstream.add,
          onError: (Object _) => downstream.destroy(),
          onDone: downstream.destroy);
      downstream
          .add(ascii.encode('HTTP/1.1 200 Connection Established\r\n\r\n'));
    },
        onError: (Object _) => upstream?.destroy(),
        onDone: () => upstream?.destroy());
  }

  Future<void> close() async {
    for (final socket in sockets) {
      socket.destroy();
    }
    await server.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Map<String, _Origin> origins;
  late _ConnectProxy proxy;

  setUpAll(() async {
    final dir = await Directory.systemTemp.createTemp('kazumi_proxy_tls_');
    PathProviderPlatform.instance = _Paths(dir.path);
    Hive.init(dir.path);
    await GStorage.init();
    origins = {
      for (final name in ['valid', 'wrong-host', 'untrusted'])
        name: await _Origin.start(name)
    };
    proxy = await _ConnectProxy.start(
        origins.values.map((origin) => origin.server.port).toSet());
    await GStorage.putSetting(SettingsKeys.enableBangumiProxy, false);
    await GStorage.putSetting(
        SettingsKeys.proxyUrl, 'http://127.0.0.1:${proxy.port}');
  });
  tearDownAll(() async {
    DioFactory.reset();
    await proxy.close();
    for (final origin in origins.values) {
      await origin.close();
    }
    await Hive.close();
  });

  Future<String> request(String kind, String certificate,
      {bool trustFixture = true}) async {
    final trust = _FixtureTrust(trustFixture: trustFixture);
    return HttpOverrides.runZoned(() async {
      final url = origins[certificate]!.url;
      if (kind == 'images') {
        final response = await ProxyAwareImageCacheManager
            .instance.config.fileService
            .get(url, headers: {'x-probe': 'preserved'});
        return utf8.decode(await response.content
            .fold<List<int>>([], (bytes, chunk) => bytes..addAll(chunk)));
      }
      final settings = NetworkConfig.fromSettings();
      // The editor's explicit config uses the same strict factory.
      final config = kind == 'editor'
          ? NetworkConfig(
              proxyHost: '127.0.0.1',
              proxyPort: proxy.port,
              connectTimeout: const Duration(seconds: 3),
              receiveTimeout: const Duration(seconds: 3),
              enableLog: false)
          : settings.copyWith(
              connectTimeout: const Duration(seconds: 3),
              receiveTimeout: const Duration(seconds: 3),
              enableLog: false);
      final dio = DioFactory.createForConfig(config);
      try {
        final result = await dio.get<String>(url,
            options: Options(headers: {'x-probe': 'preserved'}));
        return result.data!;
      } finally {
        dio.close(force: true);
      }
    }, createHttpClient: trust.createHttpClient);
  }

  for (final kind in ['api', 'images', 'editor']) {
    for (final enabled in kind == 'editor' ? [true] : [false, true]) {
      test('$kind proxy=$enabled accepts trusted matching certificate',
          () async {
        await GStorage.putSetting(SettingsKeys.proxyEnable, enabled);
        final count = proxy.targets.length;
        expect(await request(kind, 'valid'), 'verified response');
        expect(proxy.targets.length, count + (enabled ? 1 : 0));
        expect(
            origins['valid']!.requests.last, ('/image?case=tls', 'preserved'));
      });
      for (final certificate in ['wrong-host', 'untrusted']) {
        test('$kind proxy=$enabled rejects $certificate certificate', () async {
          await GStorage.putSetting(SettingsKeys.proxyEnable, enabled);
          final count = origins[certificate]!.requests.length;
          final failure = kind == 'images'
              ? isA<HandshakeException>()
              : isA<DioException>().having((e) => e.error,
                  'underlying TLS failure', isA<HandshakeException>());
          await expectLater(request(kind, certificate), throwsA(failure));
          expect(origins[certificate]!.requests.length, count,
              reason: 'Rejected certificates must never reach HTTP handling');
        });
      }
    }
  }

  test('test CA has no implicit trust; proxy toggle changes route only',
      () async {
    for (final enabled in [true, false, true]) {
      await GStorage.putSetting(SettingsKeys.proxyEnable, enabled);
      await expectLater(
          request('api', 'valid', trustFixture: false),
          throwsA(isA<DioException>().having(
              (e) => e.error, 'untrusted test CA', isA<HandshakeException>())));
      expect(await request('api', 'valid'), 'verified response');
    }
    const original = NetworkConfig(
        proxyHost: '127.0.0.1',
        proxyPort: 80,
        connectTimeout: Duration(seconds: 5),
        receiveTimeout: Duration(seconds: 6),
        sendTimeout: Duration(seconds: 7),
        enableLog: false);
    final cleared = original.copyWith(clearProxy: true);
    expect(cleared.hasProxy, false);
    expect(cleared.connectTimeout, original.connectTimeout);
    expect(cleared.receiveTimeout, original.receiveTimeout);
    expect(cleared.sendTimeout, original.sendTimeout);
    expect(cleared.enableLog, original.enableLog);
  });
}
