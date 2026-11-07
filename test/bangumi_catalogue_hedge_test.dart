import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kazumi/request/apis/bangumi_api.dart';
import 'package:kazumi/request/clients/bangumi_client.dart';
import 'package:kazumi/request/clients/bangumi_public_route.dart';
import 'package:kazumi/request/core/dio_factory.dart';
import 'package:kazumi/request/core/network_exception.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/utils/hedged_request.dart';
import 'package:logger/logger.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

Map<String, dynamic> _subject(int id) => {
      'id': id,
      'name': 'sample $id',
      'date': '2025-01-01',
      'rating': {'rank': 1, 'score': 7, 'total': 1},
      'images': <String, String>{},
    };

enum _Kind { tagged, trending, season }

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  late PathProviderPlatform paths;
  late _Adapter adapter;

  setUpAll(() async {
    Logger.level = Level.off;
    temp = await Directory.systemTemp.createTemp('catalogue_hedge_');
    paths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _Paths(temp.path);
    Hive.init(temp.path);
    await GStorage.init();
  });
  setUp(() async {
    await GStorage.putSetting(SettingsKeys.enableBangumiProxy, true);
    DioFactory.reset();
    adapter = _Adapter();
    DioFactory.apiDio.httpClientAdapter = adapter;
    // FakeAsync advances this delay; no test waits four wall-clock seconds.
    BangumiApi.hedgeDelay = catalogueHedgeDelay;
  });
  tearDown(() {
    BangumiApi.hedgeDelay = catalogueHedgeDelay;
    DioFactory.apiDio.close(force: true);
    DioFactory.reset();
  });
  tearDownAll(() async {
    await Hive.close();
    PathProviderPlatform.instance = paths;
    expect(temp.uri.pathSegments.where((s) => s.isNotEmpty).last,
        startsWith('catalogue_hedge_'));
    await temp.delete(recursive: true);
  });

  for (final kind in _Kind.values) {
    void scenario(void Function(FakeAsync, _Catalogue) body) {
      fakeAsync((clock) {
        final run = _Catalogue(kind, adapter, clock)..start();
        body(clock, run);
        expect(clock.pendingTimers.length, 0, reason: '$kind timer cleaned up');
      });
    }

    test('$kind fast primary never requests backup, including empty success',
        () {
      scenario((clock, run) {
        run.primarySuccess(null);
        expect(run.result, isEmpty);
        if (kind == _Kind.season) expect(run.calendarDayCount, 7);
        expect(run.completions, 1);
        clock.elapse(const Duration(seconds: 10));
        expect(adapter.calls, hasLength(1));
      });
    });

    test('$kind slow primary: backup wins, cancels primary, sticks on page 2',
        () {
      scenario((clock, run) {
        clock.elapse(const Duration(seconds: 3));
        expect(adapter.calls, hasLength(1));
        clock.elapse(const Duration(seconds: 1));
        expect(adapter.calls, hasLength(2));
        run.backupSuccess(2);
        expect(run.result, kind == _Kind.season ? [2, 2, 2, 2] : [2]);
        expect(adapter.calls.first.cancelled, isTrue);
        expect(adapter.calls.first.options.cancelToken!.isCancelled, isTrue);
        final previous = run.result;
        run.primarySuccess(99); // Adapter ignores cancellation deliberately.
        expect(run.result, same(previous));
        run.checkPageTwo(backup: true);
      });
    });

    for (final lateError in [false, true]) {
      test('$kind primary wins after delay; late backup error=$lateError inert',
          () {
        scenario((clock, run) {
          clock.elapse(catalogueHedgeDelay);
          final losing = adapter.calls.last;
          run.primarySuccess(1);
          expect(run.result, [1]);
          expect(losing.cancelled, isTrue);
          if (lateError) {
            losing.error();
          } else {
            losing.success(run.backupPayload(99));
          }
          clock.elapse(Duration.zero);
          expect(run.result, [1]);
          expect(run.completions, 1);
          // For season there must be no page 2 after cancelled page 1.
          expect(adapter.calls, hasLength(2));
          run.checkPageTwo(backup: false);
        });
      });
    }

    for (final empty in [false, true]) {
      test('$kind backup empty=$empty waits for later primary success', () {
        scenario((clock, run) {
          clock.elapse(catalogueHedgeDelay);
          if (empty) {
            adapter.calls.last.success(run.backupPayload(null));
          } else {
            adapter.calls.last.status(403);
          }
          clock.elapse(Duration.zero);
          expect(run.completions, 0);
          expect(adapter.calls.first.cancelled, isFalse);
          run.primarySuccess(1);
          expect(run.result, [1]);
          run.checkPageTwo(backup: false);
        });
      });
    }

    test('$kind retryable primary failure starts backup immediately once', () {
      scenario((clock, run) {
        adapter.calls.first.status(503);
        clock.elapse(Duration.zero);
        expect(adapter.calls, hasLength(2));
        clock.elapse(const Duration(seconds: 10));
        expect(adapter.calls, hasLength(2));
        run.backupSuccess(2);
        expect(run.result, isNotEmpty);
        run.checkPageTwo(backup: true);
      });
    });

    test('$kind primary failure while backup runs keeps waiting', () {
      scenario((clock, run) {
        clock.elapse(catalogueHedgeDelay);
        adapter.calls.first.status(403);
        clock.elapse(Duration.zero);
        expect(run.completions, 0);
        run.backupSuccess(2);
        expect(run.result, isNotEmpty);
      });
    });

    test('$kind both fail returns existing empty result; backup starts once',
        () {
      scenario((clock, run) {
        adapter.calls.first.status(503);
        clock.elapse(Duration.zero);
        adapter.calls.last.status(403);
        clock.elapse(Duration.zero);
        expect(run.result, isEmpty);
        expect(run.completions, 1);
        if (kind == _Kind.season) expect(run.calendarDayCount, 0);
        clock.elapse(const Duration(seconds: 10));
        expect(adapter.calls, hasLength(2));
        run.checkPageTwo(backup: false);
      });
    });

    test('$kind empty backup after primary failure returns failed result', () {
      scenario((clock, run) {
        adapter.calls.first.status(503);
        clock.elapse(Duration.zero);
        adapter.calls.last.success(run.backupPayload(null));
        clock.elapse(Duration.zero);
        expect(run.result, isEmpty);
        expect(run.completions, 1);
        if (kind == _Kind.season) expect(run.calendarDayCount, 0);
        expect(adapter.calls, hasLength(2));
        run.checkPageTwo(backup: false);
      });
    });

    for (final backupWins in [false, true]) {
      test('$kind cancelled loser is silent, backup wins=$backupWins', () {
        final messages = <LogEvent>[];
        Logger.level = Level.trace;
        Logger.addLogListener(messages.add);
        try {
          scenario((clock, run) {
            clock.elapse(catalogueHedgeDelay);
            final loser = backupWins ? adapter.calls.first : adapter.calls.last;
            if (backupWins) {
              run.backupSuccess(2);
            } else {
              run.primarySuccess(1);
            }
            expect(loser.cancelled, isTrue);
            loser.error();
            clock.elapse(Duration.zero);
            expect(messages.where((e) => e.level.index >= Level.warning.index),
                isEmpty);
          });
        } finally {
          Logger.removeLogListener(messages.add);
          Logger.level = Level.off;
        }
      });
    }

    for (final primaryCancelled in [false, true]) {
      test('$kind adapter cancellation is silent, primary=$primaryCancelled',
          () {
        final messages = <LogEvent>[];
        Logger.level = Level.trace;
        Logger.addLogListener(messages.add);
        try {
          scenario((clock, run) {
            if (!primaryCancelled) clock.elapse(catalogueHedgeDelay);
            final call = adapter.calls.last;
            // The transport can reject with cancellation without the caller
            // cancelling its token. Exercise mapped exception classification.
            call.response.completeError(DioException(
                requestOptions: call.options, type: DioExceptionType.cancel));
            clock.elapse(Duration.zero);
            if (primaryCancelled) {
              expect(run.result, isEmpty);
              expect(run.completions, 1);
              expect(adapter.calls, hasLength(1));
            } else {
              expect(run.completions, 0);
              run.primarySuccess(1);
              expect(run.result, [1]);
            }
            expect(messages.where((e) => e.level.index >= Level.warning.index),
                isEmpty);
          });
        } finally {
          Logger.removeLogListener(messages.add);
          Logger.level = Level.off;
        }
      });
    }

    for (final status in [401, 403, 429]) {
      test('$kind early non-retryable $status never starts backup', () {
        scenario((clock, run) {
          adapter.calls.first.status(status);
          clock.elapse(Duration.zero);
          expect(run.result, isEmpty);
          expect(run.completions, 1);
          if (kind == _Kind.season) expect(run.calendarDayCount, 0);
          clock.elapse(const Duration(seconds: 10));
          expect(adapter.calls, hasLength(1));
        });
      });
    }

    test('$kind late primary error after backup wins has no effect', () {
      scenario((clock, run) {
        clock.elapse(catalogueHedgeDelay);
        run.backupSuccess(2);
        adapter.calls.first.error();
        clock.elapse(Duration.zero);
        expect(run.completions, 1);
        run.checkPageTwo(backup: true);
      });
    });
  }

  test('season page 2 fails while primary pending; no partial calendar wins',
      () {
    fakeAsync((clock) {
      final run = _Catalogue(_Kind.season, adapter, clock)..start();
      clock.elapse(catalogueHedgeDelay);
      adapter.calls.last.success(run.backupPayload(2));
      clock.elapse(Duration.zero);
      expect(adapter.calls.last.options.uri.queryParameters['offset'], '20');
      adapter.calls.last.status(403);
      clock.elapse(Duration.zero);
      expect(run.completions, 0);
      run.primarySuccess(1);
      expect(run.result, [1]);
      expect(adapter.calls, hasLength(3));
      expect(clock.pendingTimers.length, 0);
    });
  });

  test('season cancellation on page 2 stops page 3 and internal route retry',
      () {
    fakeAsync((clock) {
      final run = _Catalogue(_Kind.season, adapter, clock)..start();
      clock.elapse(catalogueHedgeDelay);
      adapter.calls.last.success(run.backupPayload(2));
      clock.elapse(Duration.zero);
      final page2 = adapter.calls.last;
      run.primarySuccess(1);
      expect(page2.cancelled, isTrue);
      page2.status(503);
      clock.elapse(Duration.zero);
      clock.elapse(const Duration(seconds: 10));
      expect(adapter.calls, hasLength(3));
      expect(run.result, [1]);
      expect(clock.pendingTimers.length, 0);
    });
  });

  test('cancelled public route never retries or emits a warning/error log', () {
    fakeAsync((clock) {
      final messages = <LogEvent>[];
      Logger.level = Level.trace;
      Logger.addLogListener(messages.add);
      addTearDown(() {
        Logger.removeLogListener(messages.add);
        Logger.level = Level.off;
      });
      final token = CancelToken();
      Object? error;
      BangumiClient.instance.publicSearch(
          data: {},
          limit: 20,
          offset: 0,
          cancelToken: token).catchError((Object e) {
        error = e;
        return null;
      });
      clock.elapse(Duration.zero);
      token.cancel('hedge loser');
      clock.elapse(Duration.zero);
      expect(
          error,
          isA<NetworkException>()
              .having((e) => e.type, 'type', NetworkExceptionType.cancel));
      expect(BangumiPublicRoute.canRetry(error!), isFalse);
      expect(BangumiPublicRoute.canRetry(token.cancelError!), isFalse);
      adapter.calls.single.status(503);
      clock.elapse(Duration.zero);
      expect(adapter.calls, hasLength(1));
      expect(
          messages.where((e) => e.level.index >= Level.warning.index), isEmpty);
    });
  });

  test('later primary popular pages never hedge or switch on failure', () {
    fakeAsync((clock) {
      final run = _Catalogue(_Kind.tagged, adapter, clock)..start();
      run.primarySuccess(1);
      List<int>? next;
      run.load(offset: 24).then((value) => next = value);
      clock.elapse(Duration.zero);
      clock.elapse(const Duration(seconds: 10));
      expect(adapter.calls, hasLength(2));
      expect(adapter.calls.last.isPrimary, isTrue);
      adapter.calls.last.status(503);
      clock.elapse(Duration.zero);
      expect(next, isEmpty);
      expect(adapter.calls, hasLength(2));
      expect(clock.pendingTimers.length, 0);
    });
  });
}

class _Catalogue {
  _Catalogue(this.kind, this.adapter, this.clock);
  final _Kind kind;
  final _Adapter adapter;
  final FakeAsync clock;
  List<int>? result;
  int completions = 0;
  int? calendarDayCount;

  Future<List<int>> load({int offset = 0}) async {
    if (kind == _Kind.season) {
      final days = await BangumiApi.getBangumiMirrorSeasonCalendar(
          ['2025-01-01', '2025-04-01']);
      calendarDayCount = days.length;
      return days.expand((day) => day).map((item) => item.id).toList();
    }
    return (await BangumiApi.getBangumiMirrorPopularSubjects(
            tag: kind == _Kind.tagged ? '冒险' : '', offset: offset))
        .map((item) => item.id)
        .toList();
  }

  void start() {
    load().then((value) {
      result = value;
      completions++;
    });
    clock.elapse(Duration.zero);
    expect(adapter.calls, hasLength(1));
  }

  Object primaryPayload(int? id) => kind == _Kind.season
      ? {
          for (var i = 1; i <= 7; i++)
            '$i': [
              if (i == 3 && id != null) {'subject': _subject(id)}
            ]
        }
      : {
          'data': [if (id != null) _subject(id)]
        };

  Object backupPayload(int? id) => {
        'data': [
          if (id != null)
            kind == _Kind.trending ? {'subject': _subject(id)} : _subject(id)
        ],
        'total': id == null ? 0 : 80,
      };

  void primarySuccess(int? id) {
    adapter.calls.first.success(primaryPayload(id));
    clock.elapse(Duration.zero);
  }

  void backupSuccess(int id) {
    final pages = kind == _Kind.season ? 4 : 1;
    for (var page = 0; page < pages; page++) {
      final call = adapter.calls.last;
      expect(call.isPrimary, isFalse);
      expect(call.options.uri.queryParameters['offset'], '${page * 20}');
      if (kind == _Kind.season) {
        expect(
            call.body['filter']['air_date'], ['>=2025-01-01', '<2025-04-01']);
      } else if (kind == _Kind.tagged) {
        expect(call.body['sort'], 'heat');
        expect(call.body['filter']['tag'], ['冒险']);
      } else {
        expect(call.options.uri.path, '/p1/trending/subjects');
      }
      call.success(backupPayload(id));
      clock.elapse(Duration.zero);
    }
  }

  void checkPageTwo({required bool backup}) {
    if (kind == _Kind.season) return;
    final count = adapter.calls.length;
    List<int>? next;
    load(offset: 24).then((value) => next = value);
    clock.elapse(Duration.zero);
    expect(adapter.calls, hasLength(count + 1));
    final call = adapter.calls.last;
    expect(call.isPrimary, !backup);
    expect(call.options.uri.queryParameters['offset'], '24');
    call.success(backup ? backupPayload(3) : primaryPayload(3));
    clock.elapse(Duration.zero);
    expect(next, [3]);
  }
}

class _Call {
  _Call(this.options, this.body);
  final RequestOptions options;
  final dynamic body;
  final response = Completer<ResponseBody>();
  bool cancelled = false;
  bool get isPrimary => options.uri.path.startsWith('/kazumi/');

  void success(Object data) => response
          .complete(ResponseBody.fromString(jsonEncode(data), 200, headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType]
      }));
  void status(int status) =>
      response.complete(ResponseBody.fromString('{}', status, headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType]
      }));
  void error() => response.completeError(DioException(
      requestOptions: options, type: DioExceptionType.connectionError));
}

class _Adapter implements HttpClientAdapter {
  final calls = <_Call>[];
  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? stream,
      Future<void>? cancelFuture) async {
    final body = stream == null
        ? null
        : jsonDecode(
            utf8.decode(await stream.expand((bytes) => bytes).toList()));
    final call = _Call(options, body);
    calls.add(call);
    cancelFuture?.then((_) => call.cancelled = true);
    return call.response.future;
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
