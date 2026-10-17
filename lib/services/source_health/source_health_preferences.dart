import 'dart:convert';

import 'package:kazumi/plugins/plugins.dart';
import 'package:kazumi/services/source_health/source_health.dart';
import 'package:kazumi/services/storage/storage.dart';

class SourceHealthPreferences {
  static Map<String, dynamic> _read() {
    try {
      return Map<String, dynamic>.from(
        jsonDecode(GStorage.getSetting(SettingsKeys.sourceHealthPreferences)),
      );
    } catch (_) {
      return {};
    }
  }

  static Plugin? preferred(int subject, List<Plugin> plugins) {
    final saved = _read()['$subject'];
    if (saved is! Map) return null;
    for (final plugin in plugins) {
      if (saved['rule'] == plugin.name &&
          saved['fingerprint'] == ruleFingerprint(plugin)) {
        return plugin;
      }
    }
    return null;
  }

  static Future<void> remember(int subject, Plugin plugin) async {
    final saved = _read()..remove('$subject');
    saved['$subject'] = {
      'rule': plugin.name,
      'fingerprint': ruleFingerprint(plugin),
    };
    while (saved.length > 128) {
      saved.remove(saved.keys.first);
    }
    await GStorage.putSetting(
      SettingsKeys.sourceHealthPreferences,
      jsonEncode(saved),
    );
  }
}
