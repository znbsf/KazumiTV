import 'package:kazumi/plugins/plugins.dart';
import 'package:kazumi/plugins/rule_overlay.dart';

/// Uses the production model; baseline comparison never changes installed rules.
class BatchRuleSnapshot {
  BatchRuleSnapshot.fromJson(Map<String, dynamic> json,
      {String variant = 'effective'}) {
    if (variant != 'effective' && variant != 'base') {
      throw const FormatException('Unknown rule comparison variant');
    }
    final imported = Plugin.fromJson(json);
    final overlay = imported.tvOverlay;
    if (variant == 'base' && overlay == null) {
      throw const FormatException('Base comparison requires overlay metadata');
    }
    plugin = variant == 'base' ? Plugin.fromJson(overlay!.baseRule) : imported;
    final effective = plugin.toJson(includeLocalMetadata: false);
    identity = {
      'variant': variant,
      'overlay': variant == 'effective' && overlay != null,
      'effective_sha256': RuleOverlay.fingerprint(effective),
      'base_sha256': overlay?.baseSha256,
      'overlay_sha256':
          overlay == null ? null : RuleOverlay.fingerprint(overlay.toJson()),
      'upstream_repository': overlay?.repository,
      'upstream_commit': overlay?.commit,
      'provenance_trust':
          overlay == null ? 'unknown' : 'unverified_source_label',
    };
  }

  late final Plugin plugin;
  late final Map<String, Object?> identity;
}
