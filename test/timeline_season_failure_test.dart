import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/pages/timeline/timeline_controller.dart';
import 'package:kazumi/repositories/collect_repository.dart';
import 'package:kazumi/request/apis/bangumi_api.dart';
import 'package:kazumi/request/core/dio_factory.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:logger/logger.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

Map<String, dynamic> _subject(int id) => {
      'id': id,
      'name': 'sample $id',
      'date': '2025-01-01',
      'rating': {'rank': 1, 'score': 7, 'total': id},
      'images': <String, String>{},
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  late PathProviderPlatform paths;
  late _Adapter adapter;
  late _TrackingTimelineController controller;
  final season = DateTime(2025, 1);
  const dateRange = ['2025-01-01', '2025-04-01'];

  setUpAll(() async {
    Logger.level = Level.off;
    temp = await Directory.systemTemp.createTemp('timeline_season_failure_');
    paths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _Paths(temp.path);
    Hive.init(temp.path);
    await GStorage.init();
  });
  setUp(() async {
    await GStorage.putSetting(SettingsKeys.enableBangumiProxy, false);
    DioFactory.reset();
    adapter = _Adapter();
    DioFactory.apiDio.httpClientAdapter = adapter;
    controller = _TrackingTimelineController();
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
        startsWith('timeline_season_failure_'));
    await temp.delete(recursive: true);
  });

  test('search failure differs from a successful empty calendar page',
      () async {
    adapter.failOffset = 0;
    expect(await BangumiApi.getCalendarBySearch(dateRange, 20, 0), isEmpty);
    adapter.failOffset = null;
    adapter.empty = true;
    final result = await BangumiApi.getCalendarBySearch(dateRange, 20, 0);
    expect(result, hasLength(7));
    expect(result.every((day) => day.isEmpty), isTrue);
  });

  test('direct season page two failure clears all data and skips sorting',
      () async {
    controller.bangumiCalendar.add([BangumiItem.fromJson(_subject(99))]);
    adapter.failOffset = 20;
    await controller.loadSeason(season);
    expect(controller.isTimeOut, isTrue);
    expect(controller.bangumiCalendar, isEmpty);
    expect(controller.isLoading, isFalse);
    expect(controller.sortCalls, 0);
    expect(adapter.requests.map((o) => o.uri.queryParameters['offset']),
        ['0', '20']);
  });

  test('direct season publishes and sorts all four successful pages', () async {
    await controller.loadSeason(season);
    expect(controller.isTimeOut, isFalse);
    expect(controller.isLoading, isFalse);
    expect(controller.bangumiCalendar, hasLength(7));
    expect(
        controller.bangumiCalendar[2].map((item) => item.id), [61, 41, 21, 1]);
    expect(controller.bangumiCalendar.expand((day) => day), hasLength(4));
    expect(controller.sortCalls, 1);
    expect(adapter.requests.map((o) => o.uri.queryParameters), [
      {'limit': '20', 'offset': '0'},
      {'limit': '20', 'offset': '20'},
      {'limit': '20', 'offset': '40'},
      {'limit': '20', 'offset': '60'},
    ]);
    for (var i = 0; i < adapter.requests.length; i++) {
      final request = adapter.requests[i];
      expect(request.method, 'POST');
      expect(request.uri.host, 'api.bgm.tv');
      expect(request.uri.path, '/v0/search/subjects');
      final body = jsonDecode(adapter.bodies[i]);
      expect(body['sort'], 'rank');
      expect(body['filter']['rank'], ['>0', '<=99999']);
      expect(body['filter']['air_date'],
          ['>=2024-12-01 00:00:00.000', '<2025-03-01 00:00:00.000']);
      expect(body['filter']['tag'], ['日本']);
      expect(body['filter']['type'], [2]);
    }
  });

  test('successful empty season retains the existing timeout behavior',
      () async {
    adapter.empty = true;
    await controller.loadSeason(season);
    expect(controller.bangumiCalendar, hasLength(7));
    expect(controller.bangumiCalendar.every((day) => day.isEmpty), isTrue);
    expect(controller.isTimeOut, isTrue);
    expect(controller.isLoading, isFalse);
    expect(controller.sortCalls, 0);
    expect(adapter.requests, hasLength(4));
  });
}

class _TrackingTimelineController extends TimelineController {
  _TrackingTimelineController() : super(CollectRepository());
  int sortCalls = 0;

  @override
  void changeSort(TimelineSort sort) {
    sortCalls++;
    super.changeSort(sort);
  }
}

class _Adapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  final bodies = <String>[];
  int? failOffset;
  bool empty = false;

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? stream,
      Future<void>? cancelFuture) async {
    requests.add(options);
    bodies.add(stream == null
        ? ''
        : utf8.decode(await stream.expand((bytes) => bytes).toList()));
    final offset = int.parse(options.uri.queryParameters['offset']!);
    if (offset == failOffset) {
      throw DioException(
          requestOptions: options, type: DioExceptionType.connectionTimeout);
    }
    return ResponseBody.fromString(
      jsonEncode({
        'data': [if (!empty) _subject(offset + 1)],
        'total': empty ? 0 : 80,
      }),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType]
      },
    );
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
