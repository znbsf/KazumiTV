import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kazumi/request/clients/bangumi_client.dart';
import 'package:kazumi/request/core/dio_factory.dart';
import 'package:kazumi/request/core/network_exception.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/utils/bangumi_mirror_credentials.dart';
import 'package:logger/logger.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late PathProviderPlatform originalPaths;
  late _SearchAdapter adapter;
  const endpoint = 'https://api.bgm.tv/v0/search/subjects?limit=20&offset=40';
  final hasCredentials =
      (bangumiMirrorCredentials['id']?.trim().isNotEmpty ?? false) &&
          (bangumiMirrorCredentials['value']?.trim().isNotEmpty ?? false);

  setUpAll(() async {
    Logger.level = Level.off;
    directory =
        await Directory.systemTemp.createTemp('kazumi_metadata_search_');
    originalPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _SearchPaths(directory.path);
    Hive.init(directory.path);
    await GStorage.init();
  });

  setUp(() async {
    await GStorage.putSetting(SettingsKeys.enableBangumiProxy, true);
    await GStorage.putSetting(SettingsKeys.bangumiSyncEnable, false);
    await GStorage.putSetting(SettingsKeys.bangumiAccessToken, '');
    DioFactory.reset();
    adapter = _SearchAdapter();
    DioFactory.apiDio.httpClientAdapter = adapter;
  });

  tearDown(() {
    DioFactory.apiDio.close(force: true);
    DioFactory.reset();
  });

  tearDownAll(() async {
    await Hive.close();
    PathProviderPlatform.instance = originalPaths;
    expect(directory.absolute.path,
        startsWith(Directory.systemTemp.absolute.path));
    expect(directory.uri.pathSegments.where((part) => part.isNotEmpty).last,
        startsWith('kazumi_metadata_search_'));
    await directory.delete(recursive: true);
  });

  test(
      'public search preserves payload, pagination and chosen credentials route',
      () async {
    final payload = {
      'keyword': 'JOJO 奇妙冒险',
      'sort': 'match',
      'filter': {
        'type': [2],
        'tag': ['冒险'],
        'nsfw': false,
      },
    };
    final response = await BangumiClient.instance.post(
      endpoint,
      data: payload,
      queryParameters: {'extra_filter': 'kept'},
    );
    expect(response, {'data': <dynamic>[], 'total': 0});
    expect(adapter.requests, hasLength(1));
    final request = adapter.requests.single;
    expect(request.method, 'POST');
    expect(request.uri.host, hasCredentials ? 'api.kazumi.fyi' : 'api.bgm.tv');
    expect(request.uri.scheme, 'https');
    expect(request.uri.path, '/v0/search/subjects');
    expect(request.uri.queryParameters,
        {'limit': '20', 'offset': '40', 'extra_filter': 'kept'});
    expect(jsonDecode(adapter.bodies.single), payload);
    expect(request.headers.containsKey('Authorization'), isFalse);
    for (final name in ['X-AppId', 'X-Timestamp', 'X-Signature']) {
      expect(request.headers.containsKey(name), hasCredentials);
    }
    expect(GStorage.getSetting(SettingsKeys.enableBangumiProxy), isTrue);
    expect(GStorage.getSetting(SettingsKeys.bangumiSyncEnable), isFalse);
  });

  test('public search retains existing optional bearer token', () async {
    await GStorage.putSetting(SettingsKeys.bangumiSyncEnable, true);
    await GStorage.putSetting(SettingsKeys.bangumiAccessToken, ' saved-token ');
    await BangumiClient.instance.post(endpoint, data: {'keyword': 'JOJO'});
    expect(
        adapter.requests.single.headers['Authorization'], 'Bearer saved-token');
    expect(
        GStorage.getSetting(SettingsKeys.bangumiAccessToken), ' saved-token ');
    expect(GStorage.getSetting(SettingsKeys.bangumiSyncEnable), isTrue);
  });

  test('explicitly authenticated search retains mirror routing', () async {
    await BangumiClient.instance
        .post(endpoint, data: {'keyword': 'JOJO'}, requiresAuth: true);
    expect(adapter.requests.single.uri.host, 'api.kazumi.fyi');
  });

  test('mirror-disabled search continues to use official API', () async {
    await GStorage.putSetting(SettingsKeys.enableBangumiProxy, false);
    await BangumiClient.instance.post(endpoint, data: {'keyword': 'JOJO'});
    final request = adapter.requests.single;
    expect(request.uri.host, 'api.bgm.tv');
    expect(request.headers.containsKey('X-Signature'), isFalse);
    expect(GStorage.getSetting(SettingsKeys.enableBangumiProxy), isFalse);
  });

  test('subject details and collection writes retain existing mirror routing',
      () async {
    await BangumiClient.instance.get('https://api.bgm.tv/v0/subjects/38326');
    await BangumiClient.instance.post(
      'https://api.bgm.tv/v0/users/-/collections/38326',
      data: {'type': 2},
      requiresAuth: true,
    );
    expect(adapter.requests.map((request) => request.uri.host),
        ['api.kazumi.fyi', 'api.kazumi.fyi']);
  });

  test('explicit mirror URL retains its original route and error', () async {
    adapter.status = 401;
    await expectLater(
      BangumiClient.instance.post(
          'https://api.kazumi.fyi/v0/search/subjects?limit=20&offset=0',
          data: {'keyword': 'JOJO'}),
      throwsA(isA<NetworkException>()
          .having((error) => error.statusCode, 'status', 401)),
    );
    expect(adapter.requests, hasLength(1));
    expect(adapter.requests.single.uri.host, 'api.kazumi.fyi');
  });

  for (final status in [401, 403, 429, 503]) {
    test('HTTP $status remains classified and does not trigger another request',
        () async {
      adapter.status = status;
      await expectLater(
        BangumiClient.instance.post(endpoint, data: {'keyword': 'JOJO'}),
        throwsA(isA<NetworkException>()
            .having(
                (error) => error.type, 'type', NetworkExceptionType.badResponse)
            .having((error) => error.statusCode, 'status', status)),
      );
      expect(adapter.requests, hasLength(1));
      expect(GStorage.getSetting(SettingsKeys.enableBangumiProxy), isTrue);
    });
  }

  test('certificate failure is surfaced without retry or route changes',
      () async {
    adapter.failure = DioExceptionType.badCertificate;
    await expectLater(
      BangumiClient.instance.post(endpoint, data: {'keyword': 'JOJO'}),
      throwsA(isA<NetworkException>().having(
          (error) => error.type, 'type', NetworkExceptionType.badCertificate)),
    );
    expect(adapter.requests, hasLength(1));
  });

  test('cancelled search does not dispatch a request', () async {
    final cancel = CancelToken()..cancel('search replaced');
    await expectLater(
      BangumiClient.instance
          .post(endpoint, data: {'keyword': 'JOJO'}, cancelToken: cancel),
      throwsA(isA<NetworkException>()
          .having((error) => error.type, 'type', NetworkExceptionType.cancel)),
    );
    expect(adapter.requests, isEmpty);
  });
}

class _SearchAdapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  final bodies = <String>[];
  int status = 200;
  DioExceptionType? failure;

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    requests.add(options);
    bodies.add(requestStream == null
        ? ''
        : utf8.decode(await requestStream.expand((bytes) => bytes).toList()));
    if (failure != null) {
      throw DioException(requestOptions: options, type: failure!);
    }
    return ResponseBody.fromString(
      jsonEncode({'data': <dynamic>[], 'total': 0}),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _SearchPaths extends PathProviderPlatform {
  _SearchPaths(this.path);
  final String path;

  @override
  Future<String?> getApplicationSupportPath() async => path;
}
