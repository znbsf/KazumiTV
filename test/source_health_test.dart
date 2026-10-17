import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/modules/roads/road_module.dart';
import 'package:kazumi/modules/search/plugin_search_module.dart';
import 'package:kazumi/plugins/plugins.dart';
import 'package:kazumi/services/plugin/rule_engine_models.dart';
import 'package:kazumi/services/source_health/source_health.dart';

class FakeRule extends Plugin {
  FakeRule(String label)
      : super(
          api: '9',
          type: 'anime',
          name: label,
          version: '1',
          muliSources: true,
          useWebview: true,
          useNativePlayer: true,
          usePost: false,
          useLegacyParser: false,
          adBlocker: false,
          userAgent: '',
          baseUrl: 'https://example.invalid',
          searchURL: '',
          searchList: '',
          searchName: '',
          searchResult: '',
          chapterRoads: '',
          chapterResult: '',
          referer: '',
        );
  Future<PluginSearchResponse> Function()? search;
  int calls = 0;
  @override
  Future<PluginSearchResponse> queryBangumi(
    String keyword, {
    bool shouldRethrow = false,
    RuleCancelToken? cancelToken,
  }) async {
    calls++;
    return search != null
        ? await search!()
        : PluginSearchResponse(
            pluginName: name,
            data: [SearchItem(name: 'Target', src: '/target')],
          );
  }

  @override
  Future<List<Road>> queryChapterRoads(
    String source, {
    RuleCancelToken? cancelToken,
  }) async =>
      [
        Road(name: 'main', data: ['/ep1'], identifier: ['1']),
      ];
}

void main() {
  final now = DateTime.utc(2026, 10, 17);
  HealthRecord record(FakeRule p, {int subject = 1, DateTime? time}) =>
      HealthRecord(
        subject: subject,
        rule: p.name,
        fingerprint: ruleFingerprint(p),
        environment: 'env',
        checkedAt: time ?? now,
        stage: HealthStage.firstFrame,
        reason: 'frame_observed',
      );
  test(
    'unconfirmed cleanup stays blocked until late release completes',
    () async {
      final completion = Completer<void>();
      final run = HealthRun(cleanupTimeout: const Duration(milliseconds: 2));
      run.cleanup = () => completion.future;
      expect(await run.close(), isFalse);
      expect(run.cancelled, isTrue);
      completion.complete();
      expect(await run.close(), isTrue);
    },
  );
  test('late lease release cannot unlock a newer run', () {
    final first = HealthPlaybackLease.acquire()!;
    expect(HealthPlaybackLease.acquire(), isNull);
    first.release();
    final second = HealthPlaybackLease.acquire()!;
    first.release();
    expect(second.isOwner, isTrue);
    expect(HealthPlaybackLease.acquire(), isNull);
    second.release();
    final third = HealthPlaybackLease.acquire()!;
    expect(third.isOwner, isTrue);
    third.release();
  });
  test('player errors are classified without persisting messages or URLs', () {
    expect(
      healthPlayerError('decoder error https://secret.invalid?token=abc'),
      'decoder_or_output_error',
    );
    expect(healthPlayerError('HTTP error 403'), 'media_request_error');
    expect(
      healthPlayerError('Failed to recognize file format'),
      'media_format_error',
    );
    expect(healthPlayerError('transient warning'), isNull);
  });
  test(
    'only unique normalized title matches, never first unrelated result',
    () {
      final hit = SearchItem(name: ' Target! ', src: '/a');
      expect(
        matchHealthTitle(
          [SearchItem(name: 'Target 2', src: '/b'), hit],
          ['Target'],
        ),
        same(hit),
      );
      expect(
        matchHealthTitle(
          [hit, SearchItem(name: 'Target', src: '/c')],
          ['Target'],
        ),
        isNull,
      );
      expect(
        matchHealthTitle([SearchItem(name: 'Other', src: '/a')], ['Target']),
        isNull,
      );
    },
  );
  test(
    'record compatibility retains age but rejects changed rule/environment and future time',
    () {
      final p = FakeRule('a');
      final r = record(p);
      expect(r.current(ruleFingerprint(p), 'env', now), isTrue);
      expect(
        r.current(
          ruleFingerprint(p),
          'env',
          now.add(const Duration(hours: 24)),
        ),
        isTrue,
      );
      expect(r.current(ruleFingerprint(p), 'new-device', now), isFalse);
      p.searchURL = '/changed';
      expect(r.current(ruleFingerprint(p), 'env', now), isFalse);
      expect(
        record(
          p,
          time: now.add(const Duration(days: 1)),
        ).current(ruleFingerprint(p), 'env', now),
        isFalse,
      );
    },
  );
  test(
      'bounded versioned persistence recovers corrupt/unknown schema, contains no URLs',
      () {
    final p = FakeRule('a');
    final encoded = HealthRecordCodec.encode(
      List.generate(150, (i) => record(p, subject: i)),
    );
    final decoded = HealthRecordCodec.decode(encoded);
    expect(decoded.length, 128);
    expect(decoded.first.subject, 22);
    expect(encoded, isNot(contains(p.baseUrl)));
    expect(HealthRecordCodec.decode('{bad'), isEmpty);
    expect(HealthRecordCodec.decode('{"version":99,"records":[]}'), isEmpty);
  });
  test(
    'ranking retains old cross-title success as a lower-priority hint',
    () {
      final a = FakeRule('a'), b = FakeRule('b');
      expect(
        SourceHealthService.rank([a, b], [record(b)], 1, 'env', now).first,
        same(b),
      );
      expect(
        SourceHealthService.rank([a, b], [record(b)], 2, 'env', now).first,
        same(b),
      );
      expect(
        SourceHealthService.rank(
          [a, b],
          [record(b)],
          1,
          'env',
          now.add(const Duration(days: 2)),
        ).first,
        same(b),
      );
    },
  );
  Future<void> probe(
    SourceHealthService service,
    List<Plugin> plugins,
    HealthRun run,
    List<HealthRecord> results, {
    HealthPlaybackProbe? playback,
    bool stop = false,
  }) =>
      service.probe(
        subject: 1,
        keyword: 'Target',
        names: ['Target'],
        plugins: plugins,
        environment: 'env',
        run: run,
        playback: playback,
        stopOnFirstFrame: stop,
        onResult: (r, done, count) => results.add(r),
      );
  test(
    'serial low concurrency, maximum count and no false first-frame claim',
    () async {
      final rules = List.generate(5, (i) => FakeRule('$i'));
      final results = <HealthRecord>[];
      var active = 0, peak = 0;
      for (final p in rules) {
        p.search = () async {
          active++;
          if (active > peak) peak = active;
          await Future<void>.delayed(const Duration(milliseconds: 2));
          active--;
          return PluginSearchResponse(
            pluginName: p.name,
            data: [SearchItem(name: 'Target', src: '/target')],
          );
        };
      }
      await probe(
        SourceHealthService(maxRules: 3),
        rules,
        HealthRun(),
        results,
      );
      expect(peak, 1);
      expect(results.length, 3);
      expect(rules.last.calls, 0);
      expect(results.every((r) => r.stage == HealthStage.chapters), isTrue);
    },
  );
  test('empty successful search response is no result, not search hit',
      () async {
    final p = FakeRule('empty')
      ..search =
          () async => PluginSearchResponse(pluginName: 'empty', data: []);
    final results = <HealthRecord>[];
    await probe(SourceHealthService(), [p], HealthRun(), results);
    expect(results.single.stage, HealthStage.noMatch);
  });
  test('captcha is separate and never triggers playback', () async {
    final p = FakeRule('a')
      ..search = () async => throw const CaptchaRequiredException('a');
    final results = <HealthRecord>[];
    await probe(
      SourceHealthService(),
      [p],
      HealthRun(),
      results,
      playback: (c, r) async => fail('must not play captcha'),
    );
    expect(results.single.stage, HealthStage.captcha);
  });
  test(
    'cancel invalidates late success and prevents another request',
    () async {
      final pending = Completer<PluginSearchResponse>();
      final a = FakeRule('a')..search = () => pending.future;
      final b = FakeRule('b');
      final run = HealthRun();
      final results = <HealthRecord>[];
      final task = probe(SourceHealthService(), [a, b], run, results);
      await Future<void>.delayed(Duration.zero);
      run.cancel();
      await task;
      pending.complete(
        PluginSearchResponse(
          pluginName: 'a',
          data: [SearchItem(name: 'Target', src: '/a')],
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(results, isEmpty);
      expect(b.calls, 0);
    },
  );
  test('per-rule timeout cancels request and respects total budget', () async {
    final a = FakeRule('a')
      ..search = () => Completer<PluginSearchResponse>().future;
    final results = <HealthRecord>[];
    await probe(
      SourceHealthService(
        perRule: const Duration(milliseconds: 5),
        total: const Duration(milliseconds: 5),
      ),
      [a, FakeRule('b')],
      HealthRun(),
      results,
    );
    expect(results.single.stage, HealthStage.timeout);
  });
  test(
    'first-frame candidate stops and cleanup finishes before next rule',
    () async {
      final results = <HealthRecord>[];
      final a = FakeRule('a'), b = FakeRule('b');
      var released = false;
      await probe(
        SourceHealthService(),
        [a, b],
        HealthRun(),
        results,
        stop: true,
        playback: (c, r) async {
          r.cleanup = () async {
            await Future<void>.delayed(const Duration(milliseconds: 2));
            released = true;
          };
          return HealthStage.firstFrame;
        },
      );
      expect(released, isTrue);
      expect(b.calls, 0);
      expect(results.single.stage, HealthStage.firstFrame);
    },
  );
  test('bad match cannot start player even with previous health', () async {
    final p = FakeRule('a')
      ..search = () async => PluginSearchResponse(
            pluginName: 'a',
            data: [SearchItem(name: 'Target season 2', src: '/other')],
          );
    final results = <HealthRecord>[];
    await probe(
      SourceHealthService(),
      [p],
      HealthRun(),
      results,
      playback: (c, r) async => fail('wrong title'),
    );
    expect(results.single.stage, HealthStage.searchHit);
  });
}
