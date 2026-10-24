import 'dart:convert';

import 'package:kazumi/plugins/plugins.dart';
import 'package:kazumi/services/plugin/plugin_import_parser.dart';
import 'qa_rule_fingerprint.dart';

/// Plain production rules only. Overlay activation is postponed separately.
class BatchRuleSnapshot {
  BatchRuleSnapshot.fromJson(Map<String, dynamic> json,
      {String variant = 'effective'}) {
    if (variant != 'effective' ||
        json.containsKey('kind') ||
        json.containsKey('kazumiTvOverlay')) {
      throw const FormatException(
          'QA split accepts plain effective rules only');
    }
    final parsed = PluginImportParser.parse(jsonEncode(json));
    if (parsed.failures.isNotEmpty || parsed.plugins.length != 1) {
      throw const FormatException(
          'Rule rejected by production import validation');
    }
    plugin = parsed.plugins.single;
    identity = {
      'name': plugin.name,
      'version': plugin.version,
      'api': plugin.api,
      'variant': variant,
      'overlay': false,
      'effective_sha256': QaRuleFingerprint.fingerprint(plugin.toJson()),
      'base_sha256': null,
      'overlay_sha256': null,
      'upstream_repository': null,
      'upstream_commit': null,
      'provenance_trust': 'unknown',
    };
  }
  late final Plugin plugin;
  late final Map<String, Object?> identity;
}
