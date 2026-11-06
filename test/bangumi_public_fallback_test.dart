import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/pages/popular/tv_popular_controller.dart';
import 'package:kazumi/pages/video/video_controller.dart';
import 'package:kazumi/pages/history/history_controller.dart';
import 'package:kazumi/repositories/download_repository.dart';
import 'package:kazumi/services/download/download_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kazumi/request/apis/bangumi_api.dart';
import 'package:kazumi/request/clients/bangumi_client.dart';
import 'package:kazumi/request/clients/bangumi_public_route.dart';
import 'package:kazumi/request/core/dio_factory.dart';
import 'package:kazumi/request/core/network_exception.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/services/storage/home_catalog_cache.dart';
import 'package:kazumi/utils/bangumi_mirror_credentials.dart';
import 'package:logger/logger.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

const _next = 'https://next.bgm.tv';
final _signed = (bangumiMirrorCredentials['id']?.trim().isNotEmpty ?? false) &&
    (bangumiMirrorCredentials['value']?.trim().isNotEmpty ?? false);

Map<String, dynamic> _subject(int id) => {
      'id': id,
      'name': 'sample $id',
      'date': '2025-01-01',
      'rating': {'rank': 1, 'score': 7, 'total': 1},
      'images': <String, String>{},
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  late PathProviderPlatform paths;
  late _Adapter adapter;
  setUpAll(() async {
    Logger.level = Level.off;
    temp = await Directory.systemTemp.createTemp('bangumi_public_routes_');
    paths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _Paths(temp.path);
    Hive.init(temp.path);
    await GStorage.init();
  });
  setUp(() async {
    await GStorage.putSetting(SettingsKeys.enableBangumiProxy, true);
    await GStorage.putSetting(SettingsKeys.bangumiSyncEnable, true);
    await GStorage.putSetting(SettingsKeys.bangumiAccessToken, 'saved-token');
    DioFactory.reset();
    adapter = _Adapter();
    DioFactory.apiDio.httpClientAdapter = adapter;
  });
  tearDown(() {
    DioFactory.apiDio.close(force: true);
    DioFactory.reset();
  });
  tearDownAll(() async {
    await Hive.close();
    PathProviderPlatform.instance = paths;
    expect(temp.path, startsWith(Directory.systemTemp.path));
    expect(temp.uri.pathSegments.where((s) => s.isNotEmpty).last,
        startsWith('bangumi_public_routes_'));
    await temp.delete(recursive: true);
  });

  for (final throughController in [false, true]) {
    test(
      'episode timeouts throw without episode zero comments controller=$throughController',
      () async {
        adapter.respond = (options, _) => throw DioException(
              requestOptions: options,
              type: DioExceptionType.connectionTimeout,
            );
        final controller = VideoPageController(
          _History(),
          _Downloads(),
          _Manager(),
        );
        addTearDown(controller.dispose);
        await expectLater(
          throughController
              ? controller.queryBangumiEpisodeCommentsByID(123, 2)
              : BangumiApi.getBangumiEpisodeByID(123, 2),
          throwsA(isA<NetworkException>()),
        );
        expect(adapter.requests, hasLength(3));
        expect(
          adapter.requests.every(
            (request) => request.uri.path == '/v0/episodes',
          ),
          isTrue,
        );
        expect(adapter.requests.last.uri.host, 'api.bgm.tv');
        expect(adapter.requests.last.uri.queryParameters, {
          'subject_id': '123',
          'offset': '1',
          'limit': '1',
        });
        expect(
          adapter.requests.where(
            (request) => request.uri.path == '/p1/episodes/0/comments',
          ),
          isEmpty,
        );
        expect(controller.episodeCommentsList, isEmpty);
      },
    );
  }

  for (final kind in ['subjects', 'episodes', 'characters']) {
    test('$kind comments use anonymous compatible p1 route', () async {
      adapter.respond =
          (o, _) => kind == 'subjects' ? {'data': [], 'total': 0} : [];
      await BangumiClient.instance.get(
          '$_next/p1/$kind/123/comments?limit=20&offset=40',
          queryParameters: {'extra': 'kept'});
      expect(adapter.requests.single.uri.host,
          _signed ? 'api.kazumi.fyi' : 'next.bangumi.lat');
      expect(adapter.requests.single.uri.queryParameters,
          {'limit': '20', 'offset': '40', 'extra': 'kept'});
      expect(adapter.requests.single.headers['Authorization'], isNull);
      expect(
          adapter.requests.single.headers.containsKey('X-Signature'), _signed);
      expect(
          GStorage.getSetting(SettingsKeys.bangumiAccessToken), 'saved-token');
    });
  }

  test(
      'detail failure tries p1 mirror then direct official with no credentials',
      () async {
    adapter.respond = (o, _) {
      if (o.uri.host != 'next.bgm.tv') {
        throw DioException(
            requestOptions: o, type: DioExceptionType.connectionTimeout);
      }
      return _subject(38326);
    };
    final data = await BangumiClient.instance.get('$_next/p1/subjects/38326');
    expect(data['id'], 38326);
    expect(adapter.requests.map((o) => o.uri.host),
        ['api.kazumi.fyi', 'next.bangumi.lat', 'next.bgm.tv']);
    for (final o in adapter.requests) {
      expect(o.headers['Authorization'], isNull);
      expect(o.headers['X-Signature'], isNull);
    }
  });

  test('v0 read falls back to v0 mirror, preserving episode pagination',
      () async {
    adapter.respond = (o, _) => o.uri.host == 'api.kazumi.fyi'
        ? _Status(404)
        : {'data': [], 'total': 0};
    await BangumiClient.instance.get('https://api.bgm.tv/v0/episodes',
        queryParameters: {'subject_id': 38326, 'offset': 100, 'limit': 100});
    expect(adapter.requests.map((o) => o.uri.host),
        ['api.kazumi.fyi', 'api.bangumi.lat']);
    expect(adapter.requests.last.uri.queryParameters,
        {'subject_id': '38326', 'offset': '100', 'limit': '100'});
  });

  test(
      'HTTP 200 error envelope triggers fallback, legitimate empty list does not',
      () async {
    adapter.respond = (o, attempt) => attempt == 1
        ? {'code': 404, 'error': 'Not Found'}
        : {'data': [], 'total': 0};
    expect(await BangumiApi.getBangumiCommentsByID(38326), isNotNull);
    expect(adapter.requests, hasLength(2));
  });

  for (final status in [401, 403, 429]) {
    test('public HTTP $status does not fan out to other hosts', () async {
      adapter.respond = (_, __) => _Status(status);
      await expectLater(
          BangumiClient.instance.get('$_next/p1/calendar'),
          throwsA(isA<NetworkException>()
              .having((e) => e.statusCode, 'status', status)));
      expect(adapter.requests, hasLength(1));
    });
  }

  test('bad certificate does not trigger fallback', () async {
    adapter.respond = (o, _) => throw DioException(
        requestOptions: o, type: DioExceptionType.badCertificate);
    await expectLater(
        BangumiClient.instance.get('$_next/p1/calendar'),
        throwsA(isA<NetworkException>().having(
            (e) => e.type, 'type', NetworkExceptionType.badCertificate)));
    expect(adapter.requests, hasLength(1));
  });

  test('cancellation between attempts prevents fallback dispatch', () async {
    final token = CancelToken();
    adapter.respond = (o, _) {
      token.cancel('left page');
      throw DioException(
          requestOptions: o, type: DioExceptionType.connectionError);
    };
    await expectLater(
        BangumiClient.instance.get('$_next/p1/calendar', cancelToken: token),
        throwsA(isA<NetworkException>()
            .having((e) => e.type, 'type', NetworkExceptionType.cancel)));
    expect(adapter.requests, hasLength(1));
  });

  test('mirror off keeps official public reads and account token', () async {
    await GStorage.putSetting(SettingsKeys.enableBangumiProxy, false);
    adapter.respond = (_, __) => _Status(503);
    await expectLater(BangumiClient.instance.get('$_next/p1/calendar'),
        throwsA(isA<NetworkException>()));
    expect(adapter.requests.single.uri.host, 'next.bgm.tv');
    expect(
        adapter.requests.single.headers['Authorization'], 'Bearer saved-token');
  });

  test('authenticated reads and collection writes never enter fallback',
      () async {
    adapter.respond = (_, __) => _Status(503);
    await expectLater(
        BangumiClient.instance
            .get('https://api.bgmapi.com/v0/me', requiresAuth: true),
        throwsA(isA<NetworkException>()));
    await expectLater(
        BangumiClient.instance.post(
            'https://api.bgmapi.com/v0/users/-/collections/1',
            requiresAuth: true,
            data: {'type': 2}),
        throwsA(isA<NetworkException>()));
    expect(adapter.requests, hasLength(2));
    expect(
        adapter.requests.every((o) => o.uri.host == 'api.bgmapi.com'), isTrue);
    expect(
        adapter.requests
            .every((o) => o.headers['Authorization'] == 'Bearer saved-token'),
        isTrue);
  });

  test(
      'route allowlist excludes lookalikes, HTTP, userinfo and account endpoints',
      () {
    for (final url in [
      'https://next.bgm.tv.evil/p1/calendar',
      'http://next.bgm.tv/p1/calendar',
      'https://user@next.bgm.tv/p1/calendar',
      'https://next.bgm.tv:444/p1/calendar',
      'https://next.bgm.tv/p1/subjects/1/comments/extra',
      'https://next.bgm.tv/p1/users/me',
      'https://api.bgm.tv/v0/me',
      'https://api.bgm.tv/v0/users/x/collections',
      'https://api.kazumi.fyi/kazumi/v1/app/latest',
    ]) {
      expect(BangumiPublicRoute.match(url, 'GET'), isNull, reason: url);
    }
  });

  test('untagged home uses anonymous trends and keeps provider until refresh',
      () async {
    adapter.respond = (o, _) {
      if (o.uri.host == 'api.kazumi.fyi') {
        throw DioException(
            requestOptions: o, type: DioExceptionType.connectionTimeout);
      }
      return {
        'data': [
          {'subject': _subject(1), 'count': 100}
        ],
        'total': 1000,
      };
    };
    expect((await BangumiApi.getBangumiMirrorPopularSubjects()).single.id, 1);
    expect(adapter.requests.map((o) => o.uri.host),
        ['api.kazumi.fyi', 'next.bangumi.lat']);
    expect(adapter.requests.last.uri.path, '/p1/trending/subjects');
    expect(adapter.requests.last.uri.queryParameters,
        {'type': '2', 'limit': '24', 'offset': '0'});

    expect(
        (await BangumiApi.getBangumiMirrorPopularSubjects(offset: 24))
            .single
            .id,
        1);
    expect(adapter.requests.map((o) => o.uri.host),
        ['api.kazumi.fyi', 'next.bangumi.lat', 'next.bangumi.lat']);
    expect(adapter.requests.last.uri.path, '/p1/trending/subjects');
    expect(adapter.requests.last.uri.queryParameters,
        {'type': '2', 'limit': '24', 'offset': '24'});
    expect(adapter.requests.every((o) => o.method == 'GET'), isTrue);
    for (final request in adapter.requests.skip(1)) {
      expect(request.headers['Authorization'], isNull);
      expect(request.headers['X-Signature'], isNull);
    }

    adapter.respond = (_, __) => {
          'data': [_subject(2)]
        };
    expect((await BangumiApi.getBangumiMirrorPopularSubjects()).single.id, 2);
    expect(adapter.requests, hasLength(4));
    expect(adapter.requests.last.uri.host, 'api.kazumi.fyi');
    expect(adapter.requests.last.uri.path, '/kazumi/v1/popular/subjects');
  });

  test('untagged home tries official trends after public mirror fails',
      () async {
    adapter.respond = (o, _) => o.uri.host == 'next.bgm.tv'
        ? {
            'data': [
              {'subject': _subject(3), 'count': 100}
            ],
            'total': 1000,
          }
        : _Status(503);
    expect(
        (await BangumiApi.getBangumiMirrorPopularSubjects(limit: 12)).single.id,
        3);
    expect(adapter.requests.map((o) => o.uri.host),
        ['api.kazumi.fyi', 'next.bangumi.lat', 'next.bgm.tv']);
    for (final request in adapter.requests.skip(1)) {
      expect(request.method, 'GET');
      expect(request.uri.path, '/p1/trending/subjects');
      expect(request.uri.queryParameters,
          {'type': '2', 'limit': '12', 'offset': '0'});
      expect(request.headers['Authorization'], isNull);
      expect(request.headers['X-Signature'], isNull);
    }
  });

  test('untagged home returns empty when all trending providers fail',
      () async {
    adapter.respond = (_, __) => _Status(503);
    expect(await BangumiApi.getBangumiMirrorPopularSubjects(), isEmpty);
    expect(adapter.requests.map((o) => o.uri.host),
        ['api.kazumi.fyi', 'next.bangumi.lat', 'next.bgm.tv']);
    expect(adapter.requests.every((o) => o.method == 'GET'), isTrue);
  });

  test('TV keeps cached home cards and disk snapshot when all fallbacks fail',
      () async {
    final directory = Directory('${temp.path}/home-fallback');
    final cache = HomeCatalogCache(directory: directory);
    final updated = DateTime.now().toUtc().subtract(const Duration(hours: 1));
    await cache.write(true, [BangumiItem.fromJson(_subject(42))], updated);
    final file = File('${directory.path}/home-catalog-mirror.json');
    final before = await file.readAsString();
    final controller = TvPopularController(homeCache: cache);
    adapter.respond = (_, __) => _Status(503);

    await controller.queryBangumiByTrend(type: 'init');
    expect(controller.trendList.map((item) => item.id), [42]);
    expect(controller.homeUpdatedAt.value, updated);
    expect(controller.homeRefreshFailed.value, isTrue);
    expect(controller.isTimeOut, isFalse);
    await controller.refreshHome();
    await HomeCatalogCache.flush();
    expect(controller.trendList.map((item) => item.id), [42]);
    expect(controller.homeUpdatedAt.value, updated);
    expect(controller.homeRefreshFailed.value, isTrue);
    expect(controller.homeRefreshing.value, isFalse);
    expect(await file.readAsString(), before);
    expect(adapter.requests.map((o) => o.uri.host), [
      'api.kazumi.fyi',
      'next.bangumi.lat',
      'next.bgm.tv',
      'api.kazumi.fyi',
      'next.bangumi.lat',
      'next.bgm.tv',
    ]);
  });

  test('home fallback preserves category, offset and provider until refresh',
      () async {
    adapter.respond = (o, _) => o.uri.host == 'api.kazumi.fyi'
        ? _Status(503)
        : {
            'data': [_subject(1)],
            'total': 50
          };
    expect(
        await BangumiApi.getBangumiMirrorPopularSubjects(tag: '冒险', limit: 24),
        hasLength(1));
    expect(
        await BangumiApi.getBangumiMirrorPopularSubjects(
            tag: '冒险', limit: 24, offset: 24),
        hasLength(1));
    expect(adapter.requests.map((o) => o.uri.host),
        ['api.kazumi.fyi', 'api.bangumi.lat', 'api.bangumi.lat']);
    expect(adapter.requests.last.uri.queryParameters,
        {'limit': '24', 'offset': '24'});
    final body = jsonDecode(adapter.bodies.last);
    expect(body['filter']['tag'], ['冒险']);
    expect(body['sort'], 'heat');
    expect(adapter.requests.last.headers['Authorization'], isNull);
    expect(adapter.requests.last.headers['X-Signature'], isNull);
    adapter.respond = (_, __) => {
          'data': [_subject(2)]
        };
    expect(
        (await BangumiApi.getBangumiMirrorPopularSubjects(tag: '冒险')).single.id,
        2);
    expect(adapter.requests.last.uri.host, 'api.kazumi.fyi');
  });

  test('failure on later home page does not switch catalogue order', () async {
    adapter.respond = (_, __) => {
          'data': [_subject(1)]
        };
    await BangumiApi.getBangumiMirrorPopularSubjects(tag: '热血');
    adapter.respond = (_, __) => _Status(503);
    expect(
        await BangumiApi.getBangumiMirrorPopularSubjects(tag: '热血', offset: 24),
        isEmpty);
    expect(adapter.requests, hasLength(2));
    expect(adapter.requests.last.uri.host, 'api.kazumi.fyi');
  });

  test('empty primary home catalogue is valid and does not trigger fallback',
      () async {
    adapter.respond = (_, __) => {'data': []};
    expect(await BangumiApi.getBangumiMirrorPopularSubjects(), isEmpty);
    expect(adapter.requests, hasLength(1));
  });

  test('past season fallback preserves dates with a bounded public search',
      () async {
    adapter.respond = (o, _) => o.uri.host == 'api.kazumi.fyi'
        ? _Status(503)
        : {'data': [], 'total': 0};
    final result = await BangumiApi.getBangumiMirrorSeasonCalendar(
        ['2025-01-01', '2025-04-01']);
    expect(result, hasLength(7));
    expect(adapter.requests, hasLength(2));
    final body = jsonDecode(adapter.bodies.last);
    expect(body['filter']['air_date'], ['>=2025-01-01', '<2025-04-01']);
    expect(body['filter']['tag'], ['日本']);
    expect(adapter.requests.last.uri.host, 'api.bangumi.lat');
  });

  test('past season fallback discards page one when page two fails', () async {
    adapter.respond = (o, _) {
      if (o.uri.host == 'api.kazumi.fyi' ||
          o.uri.queryParameters['offset'] != '0') {
        return _Status(503);
      }
      return {
        'data': [_subject(1)],
        'total': 80,
      };
    };
    expect(
        await BangumiApi.getBangumiMirrorSeasonCalendar(
            ['2025-01-01', '2025-04-01']),
        isEmpty);
    final searches = adapter.requests.skip(1).toList();
    expect(searches.map((o) => o.uri.queryParameters['offset']),
        ['0', '20', '20', '20']);
    expect(searches.map((o) => o.uri.host), [
      'api.bangumi.lat',
      'api.bangumi.lat',
      'bgmapi.anibt.net',
      'api.bgm.tv',
    ]);
    for (final body in adapter.bodies.skip(1)) {
      final params = jsonDecode(body);
      expect(params['sort'], 'rank');
      expect(params['filter']['rank'], ['>0', '<=99999']);
    }
  });
}

class _Status {
  const _Status(this.code);
  final int code;
}

class _Adapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  final bodies = <String>[];
  Object? Function(RequestOptions, int) respond =
      (_, __) => <String, dynamic>{};
  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? stream,
      Future<void>? cancelFuture) async {
    requests.add(options);
    bodies.add(stream == null
        ? ''
        : utf8.decode(await stream.expand((b) => b).toList()));
    final data = respond(options, requests.length);
    return ResponseBody.fromString(jsonEncode(data is _Status ? {} : data),
        data is _Status ? data.code : 200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType]
        });
  }

  @override
  void close({bool force = false}) {}
}

class _Paths extends PathProviderPlatform {
  _Paths(this.path);
  final String path;
  @override
  Future<String?> getApplicationSupportPath() async => path;
}

class _History implements HistoryController {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Downloads implements IDownloadRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Manager implements IDownloadManager {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
