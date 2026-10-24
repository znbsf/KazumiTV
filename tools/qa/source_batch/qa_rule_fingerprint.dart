import 'dart:convert';
import 'package:crypto/crypto.dart';

/// Canonical sorted-key JSON digest for QA evidence, not provenance validation.
/// Matches historical normalized digests without importing an overlay feature.
class QaRuleFingerprint {
  static String fingerprint(Map<String, dynamic> rule) =>
      sha256.convert(utf8.encode(jsonEncode(_sorted(rule)))).toString();

  static Object? _sorted(Object? value) {
    if (value is Map) {
      final keys = value.keys.cast<String>().toList()..sort();
      return {for (final key in keys) key: _sorted(value[key])};
    }
    if (value is List) return value.map(_sorted).toList();
    return value;
  }
}
