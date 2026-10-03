import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kazumi/modules/search/search_history_module.dart';
import 'package:kazumi/pages/search/search_controller.dart';
import 'package:kazumi/repositories/collect_repository.dart';
import 'package:kazumi/repositories/search_history_repository.dart';
import 'package:kazumi/request/core/dio_factory.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _HistoryPaths extends PathProviderPlatform {
  _HistoryPaths(this.path);
  final String path;

  @override
  Future<String?> getApplicationSupportPath() async => path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temporaryDirectory;
  late SearchPageController controller;

  setUpAll(() async {
    temporaryDirectory =
        await Directory.systemTemp.createTemp('kazumi_history_retention_');
    PathProviderPlatform.instance = _HistoryPaths(temporaryDirectory.path);
    Hive.init(temporaryDirectory.path);
    await GStorage.init();
  });

  tearDownAll(() async {
    DioFactory.reset();
    await Hive.close();
    await temporaryDirectory.delete(recursive: true);
  });

  setUp(() async {
    DioFactory.reset();
    await GStorage.searchHistory.clear();
    for (var index = 0; index < 10; index++) {
      await GStorage.searchHistory
          .put('$index', SearchHistory('query $index', index));
    }
    controller =
        SearchPageController(CollectRepository(), SearchHistoryRepository());
    DioFactory.apiDio.interceptors.insert(0,
        InterceptorsWrapper(onRequest: (options, handler) {
      handler.resolve(Response(
          requestOptions: options,
          statusCode: 200,
          data: {'data': <dynamic>[]}));
    }));
  });

  test('repeating a full history entry keeps all other saved queries',
      () async {
    await controller.searchBangumi('query 5', type: 'init');
    final keywords = controller.searchHistories.map((item) => item.keyword);
    expect(keywords, hasLength(10));
    expect(keywords.first, 'query 5');
    expect(keywords.toSet(),
        {for (var index = 0; index < 10; index++) 'query $index'});
    expect(keywords.where((keyword) => keyword == 'query 5'), hasLength(1));
  });

  test('a new query at capacity replaces only the oldest saved query',
      () async {
    await controller.searchBangumi('new query', type: 'init');
    final keywords = controller.searchHistories.map((item) => item.keyword);
    expect(keywords, hasLength(10));
    expect(keywords.first, 'new query');
    expect(keywords, isNot(contains('query 0')));
    expect(keywords.toSet(), {
      'new query',
      for (var index = 1; index < 10; index++) 'query $index',
    });
  });
}
