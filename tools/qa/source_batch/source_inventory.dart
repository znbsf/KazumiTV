import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:kazumi/plugins/plugins.dart';
import 'qa_rule_fingerprint.dart';
import 'package:kazumi/request/config/api_endpoints.dart';
import 'package:kazumi/services/plugin/plugin_import_parser.dart';
import 'package:kazumi/services/source_health/source_health.dart'
    show ruleFingerprint;

/// Offline catalog preflight. Normalization and API gates stay in production.
class SourceInventory {
  static const titles = <String, Map<String, Object?>>{
    'student': {
      'work_key': 'student-council-hole',
      'keyword': '学生会也有洞',
      'names': ['学生会也有洞！', '学生会也有洞'],
      'identity_basis': 'prior_user_case_exact_title',
      'canonical_subject_id': null,
    },
    'frieren': {
      'work_key': 'frieren',
      'keyword': '葬送的芙莉莲',
      'names': ['葬送的芙莉莲'],
      'identity_basis': 'prior_user_case_exact_title',
      'canonical_subject_id': null,
    },
    'ubw': {
      'work_key': 'fate-stay-night-unlimited-blade-works',
      'keyword': 'Fate',
      'names': [
        '命运之夜 无限剑制 Fate/stay night [Unlimited Blade Works]',
        'Fate/stay night [Unlimited Blade Works]',
      ],
      'identity_basis': 'prior_verified_UBW_title_excludes_Fate_2006',
      'canonical_subject_id': null,
    },
    'dark': {
      'work_key': 'a-certain-dark-side-item',
      'keyword': '某暗部的少女共栖',
      'names': ['某暗部的少女共栖'],
      'identity_basis': 'prior_user_case_exact_title',
      'canonical_subject_id': null,
    },
  };

  static Future<Map<String, dynamic>> generate(Directory root) async {
    final manifest = _object(jsonDecode(
        await File('${root.path}/source_inventory_download.json')
            .readAsString()));
    final commit = manifest['commit'];
    if (manifest['schema_version'] != 1 ||
        manifest['repository'] != 'Predidit/KazumiRules' ||
        commit is! String ||
        !RegExp(r'^[0-9a-f]{40}$').hasMatch(commit)) {
      throw const FormatException('Invalid pinned inventory identity');
    }
    final indexBytes = await File('${root.path}/index.json').readAsBytes();
    if (sha256.convert(indexBytes).toString() != manifest['index_sha256']) {
      throw const FormatException('Index snapshot digest mismatch');
    }
    final index = jsonDecode(utf8.decode(indexBytes));
    final downloads = manifest['entries'];
    if (index is! List ||
        downloads is! List ||
        index.length != downloads.length ||
        index.length != manifest['catalog_rows']) {
      throw const FormatException('Catalog denominator mismatch');
    }
    final entries = <Map<String, dynamic>>[];
    final seen = <String>{};
    for (var i = 0; i < index.length; i++) {
      final download = _object(downloads[i]);
      final entry = <String, dynamic>{
        ...download,
        'coverage_status': 'not_run',
        'challenge_status': 'not_run',
        'upstream_commit': commit,
      };
      entries.add(entry);
      if (download['catalog_position'] != i || index[i] is! Map) {
        entry['validation'] = 'invalid_catalog_entry';
        continue;
      }
      final catalog = _object(index[i]);
      final name = catalog['name'];
      if (name is! String ||
          !RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]*$').hasMatch(name) ||
          !seen.add(name.toLowerCase()) ||
          name != download['name'] ||
          catalog['version'] != download['index_version']) {
        entry['validation'] = 'invalid_catalog_identity';
        continue;
      }
      if (download['fetch_status'] != 'downloaded') {
        entry['validation'] = 'download_gap';
        continue;
      }
      try {
        if (download['raw_path'] != 'rules/$name.json') {
          throw const FormatException('Snapshot path mismatch');
        }
        final bytes = await File('${root.path}/rules/$name.json').readAsBytes();
        if (sha256.convert(bytes).toString() != download['raw_sha256'] ||
            sha1.convert([
                  ...utf8.encode('blob ${bytes.length}\u0000'),
                  ...bytes
                ]).toString() !=
                download['git_blob_sha1']) {
          throw const FormatException('Rule snapshot digest mismatch');
        }
        final raw = _object(jsonDecode(utf8.decode(bytes)));
        entry['declared_api'] = raw['api'];
        entry['declared_version'] = raw['version'];
        entry['deprecated'] = raw['deprecated'] ?? false;
        if (raw['deprecated'] != null && raw['deprecated'] is! bool) {
          throw const FormatException('Invalid deprecated flag');
        }
        final parsed = PluginImportParser.parse(jsonEncode(raw));
        if (parsed.failures.isNotEmpty || parsed.plugins.length != 1) {
          entry['validation'] = 'production_import_rejected';
          entry['validation_errors'] = parsed.failures;
          continue;
        }
        final plugin = parsed.plugins.single;
        if (plugin.name != name ||
            plugin.version != catalog['version'].toString() ||
            raw.containsKey('kind') ||
            raw.containsKey('kazumiTvOverlay')) {
          throw const FormatException('Rule/catalog payload mismatch');
        }
        final effective = plugin.toJson();
        final fingerprint = QaRuleFingerprint.fingerprint(effective);
        entry.addAll({
          'name': plugin.name,
          'version': plugin.version,
          'api': plugin.api,
          'normalized_sha256': fingerprint,
          'app_rule_fingerprint': ruleFingerprint(plugin),
          'captcha_config_present': raw['antiCrawlerConfig'] is Map,
          'captcha_declared_enabled': plugin.antiCrawlerConfig.enabled,
          'captcha_type': plugin.antiCrawlerConfig.captchaType,
          'validation':
              raw['deprecated'] == true ? 'excluded_deprecated' : 'qualified',
          'candidate_cases': _cases(root, plugin, fingerprint, commit),
        });
      } on Object catch (error) {
        entry['validation'] = 'invalid_rule';
        entry['error_type'] = error.runtimeType.toString();
      }
    }
    final qualified =
        entries.where((entry) => entry['validation'] == 'qualified').toList();
    final plans = <Map<String, dynamic>>[];
    for (var wave = 0; wave < 3; wave++) {
      final cases = <Map<String, dynamic>>[
        for (final entry in qualified)
          _object((entry['candidate_cases'] as List)[wave])
      ];
      for (var offset = 0; offset < cases.length; offset += 24) {
        final batch = offset ~/ 24 + 1;
        final waveNumber = wave + 1;
        plans.add({
          'path': 'plans/wave-$waveNumber-batch-$batch.json',
          'wave': waveNumber,
          'cases': cases.skip(offset).take(24).toList(),
          'execution_policy': wave == 0
              ? 'initial_one_candidate_per_source'
              : 'filter_by_results_before_execution',
        });
      }
    }
    return {
      'schema_version': 1,
      'repository': manifest['repository'],
      'default_branch': manifest['default_branch'],
      'upstream_commit': commit,
      'index_sha256': manifest['index_sha256'],
      'source_verification': manifest['source_verification'],
      'client_api_level': ApiEndpoints.apiLevel,
      'counts': {
        'catalog_rows': index.length,
        'downloaded': entries
            .where((entry) => entry['fetch_status'] == 'downloaded')
            .length,
        'qualified': qualified.length,
        'invalid_or_gap': entries
            .where((entry) => !{'qualified', 'excluded_deprecated'}
                .contains(entry['validation']))
            .length,
        'excluded_deprecated': entries
            .where((entry) => entry['validation'] == 'excluded_deprecated')
            .length,
        'declared_captcha_attemptable': qualified
            .where((entry) => entry['captcha_declared_enabled'] == true)
            .length,
        'no_declared_captcha_attemptable': qualified
            .where((entry) => entry['captcha_declared_enabled'] == false)
            .length,
        'skipped_after_actual_challenge': 0,
        'actual_challenge_status_unknown': qualified.length,
        'not_attempted': qualified.length,
      },
      'entries': entries,
      'plans': plans,
      'scope':
          'catalog preflight only; no source requests or playback performed',
      'title_identity_policy':
          'known exact titles; canonical IDs unknown; runtime unique match required',
    };
  }

  static List<Map<String, dynamic>> _cases(
      Directory root, Plugin plugin, String fingerprint, String commit) {
    final keys = plugin.name.toLowerCase() == 'dm84'
        ? ['dark', 'frieren', 'student']
        : ['student', 'frieren', 'ubw'];
    return [
      for (var i = 0; i < keys.length; i++)
        {
          'id': 'inventory-${plugin.name.toLowerCase()}-q${i + 1}',
          'group': 'source-inventory',
          'source_key': plugin.name,
          'candidate_ordinal': i + 1,
          'rule_file':
              File('${root.path}/rules/${plugin.name}.json').absolute.path,
          'rule_variant': 'effective',
          'rule_provenance': {
            'upstream_repository': 'Predidit/KazumiRules',
            'upstream_commit': commit,
            'base_sha256': fingerprint,
            'effective_sha256': fingerprint,
            'overlay': false,
            'trust': 'snapshot_integrity_checked_no_signature',
          },
          ...titles[keys[i]]!,
          'road': 0,
          'episode': plugin.name.toLowerCase() == 'dm84' && i == 0 ? 1 : 0,
        }
    ];
  }

  static Future<void> write(
      Directory root, Map<String, dynamic> inventory) async {
    final encoder = const JsonEncoder.withIndent('  ');
    final contents = encoder.convert(inventory);
    await File('${root.path}/source_inventory.json')
        .writeAsString('$contents\n', flush: true);
    for (final rawPlan in inventory['plans'] as List) {
      final plan = _object(rawPlan);
      final relativePath = plan['path'];
      final file = File('${root.path}/$relativePath');
      await file.parent.create(recursive: true);
      final body = encoder.convert({
        'inventory_commit': inventory['upstream_commit'],
        'wave': plan['wave'],
        'execution_policy': plan['execution_policy'],
        'cases': plan['cases'],
      });
      await file.writeAsString('$body\n', flush: true);
    }
  }

  static Map<String, dynamic> _object(Object? value) {
    if (value is! Map) throw const FormatException('Expected JSON object');
    return Map<String, dynamic>.from(value);
  }
}
