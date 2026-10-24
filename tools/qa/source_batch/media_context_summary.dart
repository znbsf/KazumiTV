// Redacted metadata only. No file I/O, raw-value sink or capture entrypoint.
import 'dart:convert';

import 'package:crypto/crypto.dart';

bool qaMediaMetadataEnabled({
  required bool enabled,
  required bool debug,
  required String packageName,
}) {
  if (!enabled) return false;
  if (!debug || packageName != 'com.znbsf.kazumi.fluttertv.parserqa') {
    throw StateError('Isolated parserQa debug identity required');
  }
  return true;
}

Map<String, Object?> mediaContextPublicSummary({
  required String caseId,
  required String ruleSha256,
  required String episodeUrl,
  required String mediaUrl,
  required Map<String, String> headers,
  required DateTime observedAt,
}) {
  if (!RegExp(r'^[A-Za-z0-9_-]{1,80}$').hasMatch(caseId) ||
      !RegExp(r'^[a-f0-9]{64}$').hasMatch(ruleSha256)) {
    throw const FormatException('Invalid QA metadata identity');
  }
  Map<String, String> resource(String value) {
    final uri = Uri.tryParse(value);
    if (value.length > 8192 ||
        uri == null ||
        uri.host.isEmpty ||
        !['https', 'http'].contains(uri.scheme) ||
        uri.userInfo.isNotEmpty) {
      throw const FormatException('Invalid QA metadata resource');
    }
    return {
      'host': uri.host,
      'sha256': sha256.convert(utf8.encode(value)).toString()
    };
  }

  // Never read values of non-allowlisted headers, including cookies/auth.
  final allowed = <String, String>{};
  for (final key in headers.keys) {
    final normalized = key.toLowerCase();
    if (normalized != 'user-agent' && normalized != 'referer') continue;
    if (allowed.containsKey(normalized)) {
      throw const FormatException('Duplicate QA metadata header');
    }
    final value = headers[key]!;
    if (value.length > 8192) {
      throw const FormatException('QA metadata header too large');
    }
    allowed[normalized] = value;
  }
  final names = allowed.keys.toList()..sort();
  final canonical = {for (final name in names) name: allowed[name]};
  return {
    'schema_version': 1,
    'case_id': caseId,
    'rule_sha256': ruleSha256,
    'observed_at_utc': observedAt.toUtc().toIso8601String(),
    'episode': resource(episodeUrl),
    'media': resource(mediaUrl),
    'header_names': names,
    'headers_sha256':
        sha256.convert(utf8.encode(jsonEncode(canonical))).toString(),
    'expires_at_utc': null,
    'expiry_basis': 'unknown',
    'private_context_saved': false,
  };
}
