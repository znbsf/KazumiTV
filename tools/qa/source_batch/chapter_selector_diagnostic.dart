// Offline QA helper. No product entrypoint or runner imports this file.
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:kazumi/modules/roads/road_module.dart';
import 'package:kazumi/plugins/api_rule_config.dart';
import 'package:kazumi/plugins/plugins.dart';
import 'qa_rule_fingerprint.dart';
import 'package:kazumi/services/plugin/rule_engine_models.dart';
import 'package:kazumi/services/plugin/xpath_rule_strategy.dart';

/// Compares selectors against one caller-owned response, without fetching it.
/// Only the semantic rule's two chapter selectors are applied to the base.
/// Results are observations, never an overlay or a correctness/playback verdict.
/// The expected hash must identify the production-normalized episode URL.
/// Labels compare after whitespace removal. No input is logged or persisted.
class ChapterSelectorDiagnostic {
  static const maxHtmlBytes = 256 * 1024;
  static const maxSamplesPerVariant = 6;
  static const maxLabelRunes = 64;

  static Map<String, Object?> compare({
    required String rawHtml,
    required Map<String, dynamic> baseRuleJson,
    required Map<String, dynamic> semanticRuleJson,
    required String expectedEpisodeSha256,
    required String expectedEpisodeLabel,
  }) {
    final output = <String, Object?>{
      'schema_version': 1,
      'scope': 'offline_same_dom_chapter_selectors_only',
      'verdict': 'diagnostic_only_no_rule_or_playback_acceptance',
      'status': 'rejected',
    };
    // UTF-8 cannot be shorter than the UTF-16 length for a valid Dart string.
    if (rawHtml.length > maxHtmlBytes) {
      return output..['error_type'] = 'html_size_limit';
    }
    final bytes = utf8.encode(rawHtml);
    if (bytes.length > maxHtmlBytes) {
      return output..['error_type'] = 'html_size_limit';
    }
    output.addAll({
      'body_sha256': sha256.convert(bytes).toString(),
      'body_utf8_bytes': bytes.length,
    });
    if (rawHtml.trim().isEmpty) {
      return output..['error_type'] = 'empty_html';
    }
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(expectedEpisodeSha256) ||
        expectedEpisodeLabel.trim().isEmpty ||
        expectedEpisodeLabel.length > 256) {
      return output..['error_type'] = 'invalid_expected_identity';
    }

    try {
      final base = Plugin.fromJson(baseRuleJson);
      final semantic = Plugin.fromJson(semanticRuleJson);
      if (!_sameOrigin(base.baseUrl, semantic.baseUrl) ||
          base.chapterMode != RuleMode.xpath ||
          semantic.chapterMode != RuleMode.xpath) {
        return output..['error_type'] = 'requires_same_origin_xpath_rules';
      }
      final effectiveJson = base.toJson()
        ..['chapterRoads'] = semantic.chapterRoads
        ..['chapterResult'] = semantic.chapterResult;
      final candidate = Plugin.fromJson(effectiveJson);
      output.addAll({
        'base_rule': _identity(base),
        'candidate_rule': _identity(candidate),
        'semantic_source_rule': _identity(semantic),
        'selector_fields': ['chapterRoads', 'chapterResult'],
        'expected_episode_sha256': expectedEpisodeSha256,
        'expected_label': _safeText(expectedEpisodeLabel),
      });
      final before =
          _parse(rawHtml, base, expectedEpisodeSha256, expectedEpisodeLabel);
      final after = _parse(
          rawHtml, candidate, expectedEpisodeSha256, expectedEpisodeLabel);
      output.addAll({
        'status': 'observed',
        'base': before,
        'candidate': after,
        'comparison': {
          'ordered_selection_equal':
              before['status'] == 'parsed' && after['status'] == 'parsed'
                  ? before['selection_sha256'] == after['selection_sha256']
                  : null,
          'base_contains_expected_exact': before['contains_expected_exact'],
          'candidate_contains_expected_exact': after['contains_expected_exact'],
        },
      });
    } catch (error) {
      // Never stringify an exception: selector/schema errors may quote input.
      output['error_type'] = error.runtimeType.toString();
    }
    return output;
  }

  static bool _sameOrigin(String left, String right) {
    final a = Uri.tryParse(left), b = Uri.tryParse(right);
    return a != null &&
        b != null &&
        {'http', 'https'}.contains(a.scheme) &&
        a.host.isNotEmpty &&
        a.userInfo.isEmpty &&
        b.userInfo.isEmpty &&
        a.origin == b.origin;
  }

  static Map<String, Object?> _identity(Plugin rule) => {
        'name': _safeText(rule.name),
        'version': _safeText(rule.version),
        'api': _safeText(rule.api),
        'normalized_sha256': QaRuleFingerprint.fingerprint(rule.toJson()),
      };

  static String _compact(String label) => label.replaceAll(RegExp(r'\s+'), '');

  // Labels and schema identity fields are untrusted too. Only a conservative
  // plain-text alphabet is emitted, never URL/header-like text or controls.
  static String _safeText(String value) {
    if (value.runes.length > maxLabelRunes ||
        !RegExp(r'^[\p{L}\p{N} ._()（）【】\[\]、·-]*$', unicode: true)
            .hasMatch(value) ||
        RegExp(r'https?|cookie|authorization|bearer|token|password',
                caseSensitive: false)
            .hasMatch(value)) {
      return '[redacted]';
    }
    return value;
  }

  static Map<String, Object?> _parse(
      String raw, Plugin rule, String expectedHash, String expectedLabel) {
    try {
      final trace = const XPathRuleStrategy().parseChapters(
          raw,
          RuleExecutionConfig(
            pluginName: rule.name,
            baseUrl: rule.baseUrl,
            usePost: rule.usePost,
            searchMode: rule.searchMode,
            chapterMode: rule.chapterMode,
            searchUrl: rule.searchURL,
            searchList: rule.searchList,
            searchName: rule.searchName,
            searchResult: rule.searchResult,
            chapterRoads: rule.chapterRoads,
            chapterResult: rule.chapterResult,
            searchApiConfig: rule.searchApiConfig,
            chapterApiConfig: rule.chapterApiConfig,
            antiCrawlerConfig: rule.antiCrawlerConfig,
          ));
      return _summarize(
          trace.roads, trace.diagnostics.length, expectedHash, expectedLabel);
    } on XPathRuleFormatException catch (error) {
      return {
        'status': 'error',
        'error_type': 'XPathRuleFormatException',
        'kind': error.kind.name,
        'field': error.field?.name,
      };
    } catch (error) {
      return {'status': 'error', 'error_type': error.runtimeType.toString()};
    }
  }

  static Map<String, Object?> _summarize(List<Road> roads, int diagnosticCount,
      String expectedHash, String expectedLabel) {
    final first = <Map<String, Object?>>[], targets = <Map<String, Object?>>[];
    final digest = _DigestResult();
    final signature = sha256.startChunkedConversion(digest);
    var episodeCount = 0, hashMatches = 0, exactMatches = 0;
    for (var road = 0; road < roads.length; road++) {
      // Include road boundaries, including ordering, in the opaque signature.
      signature.add(utf8.encode('road:$road\n'));
      for (var episode = 0; episode < roads[road].data.length; episode++) {
        final hash =
            sha256.convert(utf8.encode(roads[road].data[episode])).toString();
        final label = roads[road].identifier[episode];
        final labelHash =
            sha256.convert(utf8.encode(_compact(label))).toString();
        final hashMatch = hash == expectedHash;
        final exact = hashMatch && _compact(label) == _compact(expectedLabel);
        if (hashMatch) hashMatches++;
        if (exact) exactMatches++;
        episodeCount++;
        signature.add(utf8.encode('$episode:$hash:$labelHash\n'));
        final sample = <String, Object?>{
          'road_index': road,
          'episode_index': episode,
          'label': _safeText(label),
          'label_sha256': labelHash,
          'url_sha256': hash,
          'expected_hash_match': hashMatch,
          'expected_exact_match': exact,
        };
        if (first.length < maxSamplesPerVariant ~/ 2) first.add(sample);
        if (hashMatch && targets.length < maxSamplesPerVariant ~/ 2) {
          targets.add(sample);
        }
      }
    }
    signature.close();
    final samples = <Map<String, Object?>>[...first];
    for (final target in targets) {
      if (!samples.any((sample) =>
          sample['road_index'] == target['road_index'] &&
          sample['episode_index'] == target['episode_index'])) {
        samples.add(target);
      }
    }
    return {
      'status': 'parsed',
      'road_count': roads.length,
      'episode_count': episodeCount,
      'diagnostic_count': diagnosticCount,
      'selection_sha256': digest.value!.toString(),
      'contains_expected_hash': hashMatches > 0,
      'contains_expected_exact': exactMatches > 0,
      'expected_hash_matches': hashMatches,
      'expected_exact_matches': exactMatches,
      'samples': samples,
    };
  }
}

class _DigestResult implements Sink<Digest> {
  Digest? value;
  @override
  void add(Digest data) => value = data;
  @override
  void close() {}
}
