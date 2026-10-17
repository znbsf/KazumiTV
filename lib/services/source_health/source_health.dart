import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:kazumi/modules/roads/road_module.dart';
import 'package:kazumi/modules/search/plugin_search_module.dart';
import 'package:kazumi/plugins/plugins.dart';
import 'package:kazumi/services/plugin/rule_engine_models.dart';

enum HealthStage {
  noMatch,
  searchHit,
  chapters,
  resolved,
  firstFrame,
  captcha,
  error,
  timeout,
}

class HealthRecord {
  const HealthRecord({
    required this.subject,
    required this.rule,
    required this.fingerprint,
    required this.environment,
    required this.checkedAt,
    required this.stage,
    required this.reason,
    this.ruleVersion = '',
    this.episode = '',
  });
  final int subject;
  final String rule, fingerprint, environment, reason, ruleVersion, episode;
  final DateTime checkedAt;
  final HealthStage stage;
  bool current(String fingerprint, String environment, DateTime now) =>
      this.fingerprint == fingerprint &&
      this.environment == environment &&
      !checkedAt.isAfter(now) &&
      now.difference(checkedAt) < const Duration(hours: 24);
  Map<String, Object> toJson() => {
        'subject': subject,
        'rule': rule,
        'fingerprint': fingerprint,
        'environment': environment,
        'ruleVersion': ruleVersion,
        'episode': episode,
        'checkedAt': checkedAt.toUtc().toIso8601String(),
        'stage': stage.name,
        'reason': reason,
      };
  factory HealthRecord.fromJson(Map<String, dynamic> j) => HealthRecord(
        subject: j['subject'] as int,
        rule: j['rule'] as String,
        fingerprint: j['fingerprint'] as String,
        environment: j['environment'] as String,
        ruleVersion: j['ruleVersion'] as String? ?? '',
        episode: j['episode'] as String? ?? '',
        checkedAt: DateTime.parse(j['checkedAt'] as String),
        stage: HealthStage.values.byName(j['stage'] as String),
        reason: j['reason'] as String,
      );
}

String ruleFingerprint(Plugin rule) =>
    sha256.convert(utf8.encode(jsonEncode(rule.toJson()))).toString();
String normalizedHealthTitle(String value) => value.toLowerCase().replaceAll(
      RegExp(r'[\s\p{P}\p{S}]', unicode: true),
      '',
    );

/// Strict unique title match. Never assume the first search hit is the target.
SearchItem? matchHealthTitle(List<SearchItem> hits, Iterable<String> names) {
  final accepted =
      names.map(normalizedHealthTitle).where((n) => n.isNotEmpty).toSet();
  final matches = hits
      .where((h) => accepted.contains(normalizedHealthTitle(h.name)))
      .toList();
  return matches.length == 1 ? matches.single : null;
}

class HealthCandidate {
  HealthCandidate(this.plugin, this.item, this.roads);
  final Plugin plugin;
  final SearchItem item;
  final List<Road> roads;
}

/// A run owns all requests. Cancellation invalidates late completions before
/// any result is persisted; only one rule is in flight at a time.
class HealthRun {
  HealthRun({this.cleanupTimeout = const Duration(seconds: 4)});
  final Duration cleanupTimeout;
  final token = RuleCancelToken();
  Future<void> Function()? cleanup;
  Future<bool> close() async {
    cancel();
    try {
      await cleanup?.call().timeout(cleanupTimeout);
      return true;
    } catch (_) {
      return false;
    }
  }

  final _cancelled = Completer<void>();
  bool get cancelled => token.isCancelled;
  void cancel() {
    if (!cancelled) {
      token.cancel();
      _cancelled.complete();
    }
  }

  Future<T> wait<T>(Future<T> future, Duration timeout) async {
    final deadline = Completer<T>();
    final timer = Timer(timeout,
        () => deadline.completeError(TimeoutException('health budget')));
    try {
      return await Future.any<T>([
        future,
        deadline.future,
        _cancelled.future.then<T>((_) => throw const HealthCancelled()),
      ]);
    } finally {
      timer.cancel();
    }
  }
}

class HealthCancelled implements Exception {
  const HealthCancelled();
}

typedef HealthPlaybackProbe = Future<HealthStage> Function(
  HealthCandidate candidate,
  HealthRun run,
);

class SourceHealthService {
  SourceHealthService({
    this.perRule = const Duration(seconds: 35),
    this.total = const Duration(minutes: 3),
    this.maxRules = 12,
    DateTime Function()? clock,
  }) : clock = clock ?? DateTime.now;
  final Duration perRule, total;
  final int maxRules;
  final DateTime Function() clock;

  Future<HealthCandidate?> inspect(
    Plugin plugin,
    String keyword,
    Iterable<String> names,
    HealthRun run,
  ) async {
    final response = await plugin.queryBangumi(
      keyword,
      shouldRethrow: true,
      cancelToken: run.token,
    );
    if (run.cancelled) throw const HealthCancelled();
    if (response.data.isEmpty) throw NoResultException(plugin.name);
    final match = matchHealthTitle(response.data, names);
    if (match == null) return null;
    final roads = await plugin.queryChapterRoads(
      match.src,
      cancelToken: run.token,
    );
    if (run.cancelled) throw const HealthCancelled();
    final usable = roads
        .where((r) => r.data.isNotEmpty && r.identifier.length == r.data.length)
        .toList();
    if (usable.isEmpty) throw ChapterErrorException(plugin.name);
    return HealthCandidate(plugin, match, usable);
  }

  Future<void> probe({
    required int subject,
    required String keyword,
    required Iterable<String> names,
    required List<Plugin> plugins,
    required String environment,
    required HealthRun run,
    required void Function(HealthRecord record, int done, int count) onResult,
    HealthPlaybackProbe? playback,
    bool stopOnFirstFrame = false,
  }) async {
    final watch = Stopwatch()..start();
    final selected = plugins.take(maxRules).toList();
    for (var i = 0; i < selected.length; i++) {
      if (run.cancelled || watch.elapsed >= total) break;
      final plugin = selected[i];
      final fingerprint = ruleFingerprint(plugin);
      final ruleVersion = plugin.version;
      final child = HealthRun();
      // The parent cancellation propagates even while a plugin is waiting.
      unawaited(run._cancelled.future.then((_) => child.cancel()));
      var episode = '';
      var stage = HealthStage.error;
      var reason = 'request_failed';
      final remaining = total - watch.elapsed;
      final timeout = remaining < perRule ? remaining : perRule;
      try {
        await child.wait(() async {
          final candidate = await inspect(plugin, keyword, names, child);
          if (candidate == null) {
            stage = HealthStage.searchHit;
            reason = 'no_unique_title_match';
            return;
          }
          episode =
              '1'; // ordinal in the first playable road; never persist a URL/title
          stage = HealthStage.chapters;
          reason = 'media_not_tested';
          if (playback != null) {
            stage = await playback(candidate, child);
            reason = stage == HealthStage.firstFrame
                ? 'frame_observed'
                : 'frame_not_observed';
          }
        }(), timeout);
      } on HealthCancelled {
        break;
      } on NoResultException {
        stage = HealthStage.noMatch;
        reason = 'no_search_results';
      } on CaptchaRequiredException {
        stage = HealthStage.captcha;
        reason = 'manual_verification_required';
      } on HealthPlaybackFailure catch (error) {
        stage = HealthStage.error;
        reason = error.reason;
      } on TimeoutException {
        stage = HealthStage.timeout;
        reason = 'time_budget_exhausted';
      } on ChapterErrorException {
        stage = HealthStage.searchHit;
        reason = 'chapters_failed';
      } catch (_) {
        reason = 'request_or_playback_failed';
      } finally {
        if (!await child.close()) run.cancel();
      }
      if (run.cancelled) break;
      onResult(
        HealthRecord(
          subject: subject,
          rule: plugin.name,
          fingerprint: fingerprint,
          environment: environment,
          ruleVersion: ruleVersion,
          episode: episode,
          checkedAt: clock(),
          stage: stage,
          reason: reason,
        ),
        i + 1,
        selected.length,
      );
      if (stopOnFirstFrame && stage == HealthStage.firstFrame) break;
    }
  }

  /// Ranking is only a hint. inspect() MUST re-query and re-match the subject.
  static List<Plugin> rank(
    List<Plugin> plugins,
    List<HealthRecord> records,
    int subject,
    String environment,
    DateTime now,
  ) {
    int score(Plugin p) {
      final valid = records.where(
        (r) =>
            r.rule == p.name &&
            r.stage == HealthStage.firstFrame &&
            r.current(ruleFingerprint(p), environment, now),
      );
      if (valid.any((r) => r.subject == subject)) return 0;
      return valid.isNotEmpty ? 1 : 2;
    }

    final indexed = plugins.asMap().entries.toList();
    indexed.sort((a, b) {
      final order = score(a.value).compareTo(score(b.value));
      return order == 0 ? a.key.compareTo(b.key) : order;
    });
    return indexed.map((e) => e.value).toList();
  }
}

/// Versioned, bounded local metadata only. Invalid documents recover empty.
class HealthRecordCodec {
  static List<HealthRecord> decode(String raw) {
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      if (j['version'] != 1) return [];
      return (j['records'] as List)
          .take(128)
          .map((e) => HealthRecord.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static String encode(List<HealthRecord> records) => jsonEncode({
        'version': 1,
        'records': records.reversed
            .take(128)
            .toList()
            .reversed
            .map((r) => r.toJson())
            .toList(),
      });
}

class HealthPlaybackFailure implements Exception {
  const HealthPlaybackFailure(this.reason);
  final String reason;
}

/// Only allow-listed categories leave the player; never persist raw messages.
String? healthPlayerError(String raw) {
  final text = raw.toLowerCase();
  if (text.contains('decoder') ||
      text.contains('codec') ||
      text.contains('video output')) {
    return 'decoder_or_output_error';
  }
  if (text.contains('failed to open') ||
      text.contains('http error') ||
      text.contains('connection')) {
    return 'media_request_error';
  }
  if (text.contains('failed to recognize') || text.contains('unsupported')) {
    return 'media_format_error';
  }
  return null;
}

/// Identity-owned lease: a late release can never unlock another run.
class HealthPlaybackLease {
  HealthPlaybackLease._();
  static HealthPlaybackLease? _owner;
  static HealthPlaybackLease? acquire() {
    if (_owner != null) return null;
    return _owner = HealthPlaybackLease._();
  }

  bool get isOwner => identical(_owner, this);
  void release() {
    if (isOwner) _owner = null;
  }
}
