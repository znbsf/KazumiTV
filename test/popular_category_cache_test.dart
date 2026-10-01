import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:kazumi/pages/popular/tv_popular_controller.dart';
import 'package:kazumi/pages/popular/popular_controller.dart';
import 'package:kazumi/request/core/dio_factory.dart';
import 'package:kazumi/services/storage/storage.dart';

class _Paths extends PathProviderPlatform {
  _Paths(this.path);
  final String path;
  @override
  Future<String?> getApplicationSupportPath() async => path;
}

List<Map<String, Object>> _subjects(int first, {int count = 24}) =>
    List.generate(
      count,
      (index) => {
        'id': first + index,
        'name': 'sample ${first + index}',
        'rating': {'rank': 1, 'score': 7.0, 'total': 1},
        'images': <String, String>{},
      },
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  late TvPopularController controller;
  late List<String> requests;
  setUpAll(() async {
    temp = await Directory.systemTemp.createTemp('category_cache_');
    PathProviderPlatform.instance = _Paths(temp.path);
    Hive.init(temp.path);
    await GStorage.init();
  });
  tearDownAll(() async {
    DioFactory.reset();
    await Hive.close();
    await temp.delete(recursive: true);
  });
  setUp(() async {
    await GStorage.putSetting(SettingsKeys.enableBangumiProxy, true);
    DioFactory.reset();
    controller = TvPopularController();
    requests = [];
    DioFactory.apiDio.interceptors.insert(
      0,
      InterceptorsWrapper(
        onRequest: (o, h) {
          requests.add(o.uri.toString());
          h.resolve(
            Response(
              requestOptions: o,
              statusCode: 200,
              data: {'data': _subjects((requests.length - 1) * 24 + 1)},
            ),
          );
        },
      ),
    );
  });

  test('non-TV controller retains upstream request behavior', () async {
    final upstreamController = PopularController();
    upstreamController.setCurrentTag('A');
    await upstreamController.queryBangumiByTag(type: 'init');
    await upstreamController.queryBangumiByTag(type: 'init');
    expect(requests.length, 2);
  });

  Future<void> select(String tag) async {
    controller.setCurrentTag(tag);
    await controller.queryBangumiByTag(type: 'init');
  }

  test(
    'returning to a category restores pages without requesting again',
    () async {
      await select('A');
      await controller.queryBangumiByTag();
      final ids = controller.bangumiList.map((e) => e.id).toList();
      await select('B');
      await select('A');
      expect(requests.length, 3);
      expect(controller.bangumiList.map((e) => e.id), ids);
      expect(controller.isLoadingMore, false);
      await controller.queryBangumiByTag();
      expect(Uri.parse(requests.last).queryParameters['offset'], '48');
    },
  );

  test('least recently used categories are evicted', () async {
    for (var i = 0; i < 8; i++) {
      await select('$i');
    }
    await select('0');
    expect(requests.length, 8);
    await select('8');
    await select('0');
    expect(requests.length, 9);
    await select('1');
    expect(requests.length, 10);
  });

  test('empty or failed results remain retryable', () async {
    DioFactory.apiDio.interceptors.insert(
      0,
      InterceptorsWrapper(
        onRequest: (o, h) {
          requests.add('empty');
          h.resolve(
            Response(requestOptions: o, statusCode: 200, data: {'data': []}),
          );
        },
      ),
    );
    await select('empty');
    await select('empty');
    expect(requests.length, 2);
  });

  void respond(
    RequestOptions options,
    RequestInterceptorHandler handler,
    List<Map<String, Object>> subjects,
  ) {
    handler.resolve(
      Response(
        requestOptions: options,
        statusCode: 200,
        data: {'data': subjects},
      ),
    );
  }

  test('a short mirror trend page stops automatic loading', () async {
    DioFactory.apiDio.interceptors.insert(
      0,
      InterceptorsWrapper(
        onRequest: (options, handler) {
          requests.add(options.uri.toString());
          respond(options, handler, _subjects(1, count: 5));
        },
      ),
    );
    await controller.queryBangumiByTrend();
    await controller.queryBangumiByTrend();
    expect(controller.trendList.map((item) => item.id), [1, 2, 3, 4, 5]);
    expect(controller.canLoadMore, false);
    expect(requests.length, 1);
  });

  test(
    'empty trends stop until an explicit retry without advancing the cursor',
    () async {
      DioFactory.apiDio.interceptors.insert(
        0,
        InterceptorsWrapper(
          onRequest: (options, handler) {
            requests.add(options.uri.toString());
            respond(options, handler, requests.length == 1 ? [] : _subjects(1));
          },
        ),
      );
      await controller.queryBangumiByTrend();
      await controller.queryBangumiByTrend();
      expect(requests.length, 1);
      expect(controller.isTimeOut, true);
      expect(controller.canLoadMore, false);
      await controller.queryBangumiByTrend(type: 'retry');
      expect(requests.length, 2);
      expect(Uri.parse(requests.last).queryParameters['offset'], '0');
      expect(controller.trendList.length, 24);
      expect(controller.isTimeOut, false);
      expect(controller.canLoadMore, true);
    },
  );

  test(
    'a repeated full trend page stops without duplicate card identities',
    () async {
      DioFactory.apiDio.interceptors.insert(
        0,
        InterceptorsWrapper(
          onRequest: (options, handler) {
            requests.add(options.uri.toString());
            respond(options, handler, _subjects(1));
          },
        ),
      );
      await controller.queryBangumiByTrend();
      await controller.queryBangumiByTrend();
      await controller.queryBangumiByTrend();
      expect(controller.trendList.length, 24);
      expect(controller.trendList.map((item) => item.id).toSet().length, 24);
      expect(controller.canLoadMore, false);
      expect(requests.length, 2);
    },
  );

  test(
    'trends stop after 42 pages and retry cannot bypass the 1008 item cap',
    () async {
      for (var page = 0; page < 43; page++) {
        await controller.queryBangumiByTrend();
      }
      expect(controller.trendList.length, 1008);
      expect(requests.length, 42);
      expect(Uri.parse(requests.last).queryParameters['offset'], '984');
      expect(controller.canLoadMore, false);
      await controller.queryBangumiByTrend(type: 'retry');
      expect(requests.length, 42);
      await controller.queryBangumiByTrend(type: 'init');
      expect(controller.trendList.length, 24);
      expect(requests.length, 43);
      expect(Uri.parse(requests.last).queryParameters['offset'], '0');
    },
  );

  test(
    'mirror tag paging advances the source cursor despite overlapping IDs',
    () async {
      DioFactory.apiDio.interceptors.insert(
        0,
        InterceptorsWrapper(
          onRequest: (options, handler) {
            requests.add(options.uri.toString());
            respond(options, handler, _subjects(requests.length == 1 ? 1 : 13));
          },
        ),
      );
      await select('A');
      await controller.queryBangumiByTag();
      expect(controller.bangumiList.length, 36);
      expect(controller.canLoadMore, true);
      await controller.queryBangumiByTag();
      await controller.queryBangumiByTag();
      expect(controller.bangumiList.map((item) => item.id).toSet().length, 36);
      expect(requests.length, 3);
      expect(Uri.parse(requests.last).queryParameters['offset'], '48');
      expect(controller.canLoadMore, false);
    },
  );

  test('cached category restores its own exhaustion state', () async {
    DioFactory.apiDio.interceptors.insert(
      0,
      InterceptorsWrapper(
        onRequest: (options, handler) {
          requests.add(options.uri.toString());
          final count = options.uri.queryParameters['tag'] == 'A' ? 2 : 24;
          respond(
            options,
            handler,
            _subjects(requests.length * 100, count: count),
          );
        },
      ),
    );
    await select('A');
    expect(controller.canLoadMore, false);
    await select('B');
    expect(controller.canLoadMore, true);
    await select('A');
    await controller.queryBangumiByTag();
    expect(controller.bangumiList.length, 2);
    expect(controller.canLoadMore, false);
    expect(requests.length, 2);
  });

  test(
    'cached long category keeps all loaded rows and the matching cursor',
    () async {
      await select('A');
      for (var page = 1; page < 11; page++) {
        await controller.queryBangumiByTag();
      }
      final ids = controller.bangumiList.map((item) => item.id).toList();
      expect(ids.length, 264);
      await select('B');
      await select('A');
      expect(controller.bangumiList.map((item) => item.id), ids);
      expect(requests.length, 12);
      await controller.queryBangumiByTag();
      expect(Uri.parse(requests.last).queryParameters['offset'], '264');
      expect(controller.bangumiList.length, 288);
    },
  );

  test(
    'a failed append keeps loaded cards and retries only on explicit intent',
    () async {
      DioFactory.apiDio.interceptors.insert(
        0,
        InterceptorsWrapper(
          onRequest: (options, handler) {
            requests.add(options.uri.toString());
            if (requests.length == 2) {
              handler.reject(
                DioException(
                  requestOptions: options,
                  type: DioExceptionType.connectionError,
                  error: 'fixture connection failure',
                ),
              );
            } else {
              respond(
                options,
                handler,
                _subjects(requests.length == 1 ? 1 : 25),
              );
            }
          },
        ),
      );
      await select('A');
      await controller.queryBangumiByTag();
      await controller.queryBangumiByTag();
      expect(requests.length, 2);
      expect(controller.bangumiList.length, 24);
      expect(controller.isTimeOut, false);
      expect(controller.canLoadMore, false);
      await controller.queryBangumiByTag(type: 'retry');
      expect(requests.length, 3);
      expect(Uri.parse(requests.last).queryParameters['offset'], '24');
      expect(
        controller.bangumiList.map((item) => item.id),
        List.generate(48, (index) => index + 1),
      );
      expect(controller.canLoadMore, true);
    },
  );

  test(
    'direct random tag batches deduplicate and stop on no progress',
    () async {
      await GStorage.putSetting(SettingsKeys.enableBangumiProxy, false);
      DioFactory.apiDio.interceptors.insert(
        0,
        InterceptorsWrapper(
          onRequest: (options, handler) {
            requests.add(options.uri.toString());
            respond(options, handler, _subjects(1, count: 100));
          },
        ),
      );
      await select('A');
      await controller.queryBangumiByTag();
      await controller.queryBangumiByTag();
      expect(requests.length, 2);
      expect(controller.bangumiList.length, 100);
      expect(controller.canLoadMore, false);
    },
  );

  test(
    'direct random sampling is bounded even when every short sample is new',
    () async {
      await GStorage.putSetting(SettingsKeys.enableBangumiProxy, false);
      DioFactory.apiDio.interceptors.insert(
        0,
        InterceptorsWrapper(
          onRequest: (options, handler) {
            requests.add(options.uri.toString());
            respond(
              options,
              handler,
              _subjects(requests.length * 100, count: 10),
            );
          },
        ),
      );
      await select('A');
      for (var sample = 1; sample < 12; sample++) {
        await controller.queryBangumiByTag();
      }
      expect(requests.length, 11);
      expect(controller.bangumiList.length, 110);
      expect(controller.canLoadMore, false);
    },
  );

  test(
    'direct tag samples cannot append more than 1008 unique cards',
    () async {
      await GStorage.putSetting(SettingsKeys.enableBangumiProxy, false);
      DioFactory.apiDio.interceptors.insert(
        0,
        InterceptorsWrapper(
          onRequest: (options, handler) {
            requests.add(options.uri.toString());
            respond(
              options,
              handler,
              _subjects((requests.length - 1) * 100 + 1, count: 100),
            );
          },
        ),
      );
      await select('A');
      for (var sample = 1; sample < 12; sample++) {
        await controller.queryBangumiByTag();
      }
      expect(requests.length, 11);
      expect(controller.bangumiList.length, 1008);
      expect(controller.canLoadMore, false);
    },
  );

  test(
    'old A and B responses cannot replace a newer A request or its loading',
    () async {
      final pending = <Completer<(RequestOptions, RequestInterceptorHandler)>>[
        for (var i = 0; i < 3; i++) Completer(),
      ];
      DioFactory.apiDio.interceptors.insert(
        0,
        InterceptorsWrapper(
          onRequest: (options, handler) {
            requests.add(options.uri.toString());
            pending[requests.length - 1].complete((options, handler));
          },
        ),
      );
      controller.setCurrentTag('A');
      final oldA = controller.queryBangumiByTag(type: 'init');
      final first = await pending[0].future;
      controller.setCurrentTag('B');
      final oldB = controller.queryBangumiByTag(type: 'init');
      final second = await pending[1].future;
      controller.setCurrentTag('A');
      final newA = controller.queryBangumiByTag(type: 'init');
      final third = await pending[2].future;
      respond(first.$1, first.$2, _subjects(1));
      await oldA;
      respond(second.$1, second.$2, _subjects(101));
      await oldB;
      expect(controller.bangumiList, isEmpty);
      expect(controller.isLoadingMore, true);
      respond(third.$1, third.$2, _subjects(201));
      await newA;
      expect(controller.bangumiList.first.id, 201);
      expect(controller.isLoadingMore, false);
    },
  );

  test(
    'a cached category cannot revive an old append or clear its replacement',
    () async {
      await select('A');
      final pending = <Completer<(RequestOptions, RequestInterceptorHandler)>>[
        for (var i = 0; i < 2; i++) Completer(),
      ];
      DioFactory.apiDio.interceptors.insert(
        0,
        InterceptorsWrapper(
          onRequest: (options, handler) {
            requests.add(options.uri.toString());
            pending[requests.length - 2].complete((options, handler));
          },
        ),
      );
      final oldAppend = controller.queryBangumiByTag();
      final first = await pending[0].future;
      controller.setCurrentTag('B');
      controller.setCurrentTag('A');
      await controller.queryBangumiByTag(type: 'init');
      final replacement = controller.queryBangumiByTag();
      final second = await pending[1].future;
      respond(first.$1, first.$2, _subjects(25));
      await oldAppend;
      expect(controller.bangumiList.length, 24);
      expect(controller.isLoadingMore, true);
      expect(controller.canLoadMore, false);
      respond(second.$1, second.$2, _subjects(101));
      await replacement;
      expect(controller.bangumiList.length, 48);
      expect(controller.bangumiList[24].id, 101);
      expect(controller.isLoadingMore, false);
      expect(controller.canLoadMore, true);
    },
  );

  test(
    'late trends cache results without ending a newer category loading',
    () async {
      final pending = <Completer<(RequestOptions, RequestInterceptorHandler)>>[
        for (var i = 0; i < 2; i++) Completer(),
      ];
      DioFactory.apiDio.interceptors.insert(
        0,
        InterceptorsWrapper(
          onRequest: (options, handler) {
            requests.add(options.uri.toString());
            pending[requests.length - 1].complete((options, handler));
          },
        ),
      );
      final trend = controller.queryBangumiByTrend();
      final first = await pending[0].future;
      controller.setCurrentTag('A');
      final tag = controller.queryBangumiByTag(type: 'init');
      final second = await pending[1].future;
      respond(first.$1, first.$2, _subjects(1));
      await trend;
      expect(controller.trendList.length, 24);
      expect(controller.bangumiList, isEmpty);
      expect(controller.isLoadingMore, true);
      respond(second.$1, second.$2, _subjects(101));
      await tag;
      controller.setCurrentTag('');
      expect(controller.trendList.first.id, 1);
      expect(controller.isLoadingMore, false);
      expect(controller.canLoadMore, true);
      expect(requests.length, 2);
    },
  );

  test(
    'refreshing trends invalidates the earlier request and its finalizer',
    () async {
      final pending = <Completer<(RequestOptions, RequestInterceptorHandler)>>[
        for (var i = 0; i < 2; i++) Completer(),
      ];
      DioFactory.apiDio.interceptors.insert(
        0,
        InterceptorsWrapper(
          onRequest: (options, handler) {
            requests.add(options.uri.toString());
            pending[requests.length - 1].complete((options, handler));
          },
        ),
      );
      final old = controller.queryBangumiByTrend();
      final first = await pending[0].future;
      final refreshed = controller.queryBangumiByTrend(type: 'init');
      final second = await pending[1].future;
      respond(first.$1, first.$2, _subjects(1));
      await old;
      expect(controller.trendList, isEmpty);
      expect(controller.isLoadingMore, true);
      respond(second.$1, second.$2, _subjects(101));
      await refreshed;
      expect(controller.trendList.first.id, 101);
      expect(controller.isLoadingMore, false);
    },
  );
}
