import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/modules/search/plugin_search_module.dart';
import 'package:kazumi/services/source_health/source_health.dart';
import 'source_health_test.dart' show FakeRule;

void main() {
  final now = DateTime.utc(2026, 10, 17);
  HealthRecord rec(FakeRule rule,
          {int subject = 1,
          int days = 0,
          HealthStage stage = HealthStage.firstFrame,
          String reason = 'frame_observed',
          String env = 'env'}) =>
      HealthRecord(
          subject: subject,
          rule: rule.name,
          fingerprint: ruleFingerprint(rule),
          environment: env,
          checkedAt: now.subtract(Duration(days: days)),
          stage: stage,
          reason: reason);

  test('v1 success migrates, failure does not fabricate prior success', () {
    final p = FakeRule('a');
    final migrated = HealthRecordCodec.decode(jsonEncode({
      'version': 1,
      'records': [
        rec(p).toJson(),
        rec(p, subject: 2, stage: HealthStage.noMatch).toJson()
      ]
    }));
    expect(migrated.first.success, isNotNull);
    expect(migrated.last.success, isNull);
    expect(jsonDecode(HealthRecordCodec.encode(migrated))['version'], 2);
    expect(
        HealthRecordCodec.decode(HealthRecordCodec.encode(migrated)).length, 2);
  });
  test(
      'latest failure preserves last success and late result cannot overwrite newer attempt',
      () {
    final p = FakeRule('a');
    var records = HealthRecordCodec.merge([], rec(p, days: 10));
    records = HealthRecordCodec.merge(
        records, rec(p, stage: HealthStage.error, reason: 'parse_failed'));
    expect(records.single.stage, HealthStage.error);
    expect(records.single.success!.checkedAt,
        now.subtract(const Duration(days: 10)));
    records = HealthRecordCodec.merge(records, rec(p, days: 4));
    expect(records.single.stage, HealthStage.error);
    expect(records.single.success!.checkedAt,
        now.subtract(const Duration(days: 4)));
    records = HealthRecordCodec.decode(HealthRecordCodec.encode(records));
    expect(records.single.success!.stage, HealthStage.firstFrame);
    expect(records.single.reason, 'parse_failed');
  });
  test(
      'rule and environment histories stay separate and mismatched nested success is rejected',
      () {
    final p = FakeRule('a');
    final old = rec(p);
    p.version = '2';
    var records = HealthRecordCodec.merge([old], rec(p));
    records = HealthRecordCodec.merge(records, rec(p, env: 'new-env'));
    expect(records.length, 3);
    final corrupt = jsonEncode({
      'version': 2,
      'records': [
        {'latestAttempt': rec(p).toJson(), 'lastSuccess': old.toJson()}
      ]
    });
    expect(HealthRecordCodec.decode(corrupt), isEmpty);
  });
  test('freshness bands retain old success and exclude future timestamps', () {
    final a = FakeRule('a'), b = FakeRule('b');
    expect(rec(a).freshnessBand(now), 0);
    expect(rec(a, days: 1).freshnessBand(now), 1);
    expect(rec(a, days: 7).freshnessBand(now), 2);
    expect(
        SourceHealthService.rank([a, b], [rec(b, days: 90)], 2, 'env', now)
            .first,
        b);
    expect(
        SourceHealthService.rank([a, b], [rec(b, days: -1)], 2, 'env', now)
            .first,
        a);
    expect(
        SourceHealthService.rank([a, b], [rec(b)], 2, 'env', now,
                useGlobal: false)
            .first,
        a);
  });
  test('environment change retains weak site hint but rule change removes it',
      () {
    final a = FakeRule('a'), b = FakeRule('b');
    final old = rec(b);
    expect(
        SourceHealthService.rank([a, b], [old], 2, 'changed-device', now).first,
        b);
    b.version = '2';
    expect(SourceHealthService.rank([a, b], [old], 2, 'env', now).first, a);
  });
  test(
      'recent same-title failure ranks below unmeasured but noMatch does not poison another title',
      () {
    final a = FakeRule('a'), b = FakeRule('b');
    final records = HealthRecordCodec.merge([rec(b, days: 1)],
        rec(b, stage: HealthStage.noMatch, reason: 'no_search_results'));
    expect(SourceHealthService.rank([b, a], records, 1, 'env', now).first, a);
    expect(SourceHealthService.rank([a, b], records, 2, 'env', now).first, b);
    expect(records.single.success, isNotNull);
  });
  test(
      'site failure weakly demotes global success; device decode failure stays local',
      () {
    final a = FakeRule('a'), b = FakeRule('b');
    final successes = [rec(a), rec(b)];
    final site = HealthRecordCodec.merge(
        successes, rec(a, stage: HealthStage.error, reason: 'request_failed'));
    expect(SourceHealthService.rank([a, b], site, 2, 'env', now).first, b);
    final decoder = HealthRecordCodec.merge(successes,
        rec(a, stage: HealthStage.error, reason: 'decoder_or_output_error'));
    expect(SourceHealthService.rank([a, b], decoder, 2, 'env', now).first, a);
  });
  Future<HealthCandidate?> reuse(
          List<FakeRule> rules, List<HealthRecord> records,
          {FakeRule? preferred, bool global = true}) =>
      SourceHealthService(clock: () => now).reuseRecorded(
          plugins: rules,
          records: records,
          subject: 2,
          keyword: 'Target',
          names: ['Target'],
          environment: 'env',
          run: HealthRun(),
          preferred: preferred,
          useGlobal: global);
  test(
      'no success means no search, player or probe, even with manual preference',
      () async {
    final a = FakeRule('a');
    expect(await reuse([a], [], preferred: a), isNull);
    expect(
        await reuse([a], [rec(a, stage: HealthStage.chapters)], preferred: a),
        isNull);
    expect(a.calls, 0);
  });
  test(
      'reuse searches only one recorded rule and rematches real target, never fanout',
      () async {
    final a = FakeRule('a'), b = FakeRule('b'), untested = FakeRule('untested');
    a.search = () async => PluginSearchResponse(
        pluginName: 'a', data: [SearchItem(name: 'Other', src: '/wrong')]);
    expect(
        await reuse([untested, a, b], [rec(a), rec(b)], preferred: a), isNull);
    expect(a.calls, 1);
    expect(b.calls, 0);
    expect(untested.calls, 0);
  });
  test(
      'manual eligible preference precedes global ranking and old success still usable',
      () async {
    final a = FakeRule('a'), b = FakeRule('b');
    final result =
        await reuse([a, b], [rec(a), rec(b, days: 100)], preferred: b);
    expect(result!.plugin, b);
    expect(result.item.name, 'Target');
    expect(a.calls, 0);
    expect(b.calls, 1);
  });
  test(
      'global disabled and edited rule cannot reuse foreign or stale-fingerprint success',
      () async {
    final a = FakeRule('a');
    final old = rec(a);
    expect(await reuse([a], [old], global: false), isNull);
    a.version = '2';
    expect(await reuse([a], [old]), isNull);
    expect(a.calls, 0);
  });
  test(
      'failed recorded request returns manual without querying another successful source',
      () async {
    final a = FakeRule('a'), b = FakeRule('b');
    a.search = () async => throw StateError('offline');
    expect(await reuse([a, b], [rec(a), rec(b)]), isNull);
    expect(a.calls, 1);
    expect(b.calls, 0);
  });
}
