import 'dart:convert';

import 'package:crypto/crypto.dart';

/// A local, data-only overlay pinned to one normalized upstream rule.
/// Version 1 does not load repositories, scripts, or playback adapters.
class RuleOverlay {
  static const kind = 'kazumi-tv-rule-overlay';
  static const metadataKey = 'kazumiTvOverlay';
  static const schemaVersion = 1;
  static const maxBytes = 256 * 1024;

  static const stringFields = {
    'baseURL',
    'searchURL',
    'searchList',
    'searchName',
    'searchResult',
    'chapterRoads',
    'chapterResult',
    'userAgent',
    'referer',
    'searchApiConfig.sourceTemplate',
  };
  static const boolFields = {'usePost', 'useLegacyParser', 'adBlocker'};

  RuleOverlay._({
    required this.repository,
    required this.commit,
    required this.baseSha256,
    required Map<String, dynamic> baseRule,
    required Map<String, dynamic> overrides,
  })  : _baseRule = _copy(baseRule),
        overrides = Map.unmodifiable(overrides);

  final String repository;
  final String commit;
  final String baseSha256;
  final Map<String, dynamic> _baseRule;
  final Map<String, dynamic> overrides;

  Map<String, dynamic> get baseRule => _copy(_baseRule);

  /// [baseRule] must be Plugin.toJson() without local metadata.
  factory RuleOverlay.create({
    required String repository,
    required String commit,
    required Map<String, dynamic> baseRule,
    required Map<String, dynamic> overrides,
  }) =>
      RuleOverlay.fromJson({
        'kind': kind,
        'schemaVersion': schemaVersion,
        'upstream': {'repository': repository, 'commit': commit},
        'baseSha256': fingerprint(baseRule),
        'baseRule': baseRule,
        'overrides': overrides,
      });

  factory RuleOverlay.fromJson(Map<String, dynamic> json) {
    const keys = {
      'kind',
      'schemaVersion',
      'upstream',
      'baseSha256',
      'baseRule',
      'overrides',
    };
    if (json.keys.any((key) => !keys.contains(key)) ||
        json['kind'] != kind ||
        json['schemaVersion'] != schemaVersion) {
      throw const FormatException('不支持的 TV 覆盖格式或版本');
    }
    if (utf8.encode(jsonEncode(json)).length > maxBytes) {
      throw const FormatException('TV 覆盖文件超过 256 KiB');
    }
    final upstream = _object(json['upstream']);
    if (upstream.keys.any((key) => key != 'repository' && key != 'commit') ||
        upstream['repository'] != 'Predidit/KazumiRules' ||
        upstream['commit'] is! String ||
        !RegExp(r'^[0-9a-f]{40}$').hasMatch(upstream['commit'] as String)) {
      throw const FormatException('TV 覆盖需要官方规则仓库及完整提交 SHA');
    }
    final base = _object(json['baseRule']);
    if (base.containsKey(metadataKey) ||
        base.containsKey('kind') ||
        (base['name'] is! String) ||
        (base['name'] as String).trim().isEmpty ||
        json['baseSha256'] is! String ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(json['baseSha256'] as String) ||
        fingerprint(base) != json['baseSha256']) {
      throw const FormatException('TV 覆盖基础规则或摘要不匹配');
    }
    final overrides = _object(json['overrides']);
    if (overrides.isEmpty) {
      throw const FormatException('TV 覆盖内容不能为空');
    }
    for (final entry in overrides.entries) {
      final field = entry.key;
      if (stringFields.contains(field)) {
        final value = entry.value;
        if (value is! String || value.length > 8192) {
          throw FormatException('TV 覆盖字段 $field 必须为有限长度文本');
        }
        if ((field == 'userAgent' || field == 'referer') &&
            (value.contains('\r') || value.contains('\n'))) {
          throw const FormatException('播放请求头不能包含换行');
        }
        if (field == 'searchApiConfig.sourceTemplate' &&
            value.isNotEmpty &&
            !value.contains('@source')) {
          throw const FormatException('详情页地址模板必须引用 @source');
        }
        if ({'baseURL', 'searchURL', 'referer'}.contains(field) &&
            value.isNotEmpty) {
          final uri = Uri.tryParse(value);
          if (uri == null ||
              !{'http', 'https'}.contains(uri.scheme) ||
              uri.host.isEmpty ||
              uri.userInfo.isNotEmpty) {
            throw FormatException('TV 覆盖字段 $field 需要 HTTP(S) 地址');
          }
        }
      } else if (!boolFields.contains(field) || entry.value is! bool) {
        throw FormatException('不支持的 TV 覆盖字段或类型：$field');
      }
    }
    return RuleOverlay._(
      repository: upstream['repository'] as String,
      commit: upstream['commit'] as String,
      baseSha256: json['baseSha256'] as String,
      baseRule: base,
      overrides: overrides,
    );
  }

  bool matchesBase(Map<String, dynamic> normalizedRule) =>
      fingerprint(normalizedRule) == baseSha256;

  Map<String, dynamic> apply(Map<String, dynamic> normalizedRule) {
    if (!matchesBase(normalizedRule)) {
      throw const FormatException('上游基础规则已变化，需重新审查 TV 覆盖');
    }
    final effective = _copy(normalizedRule);
    for (final entry in overrides.entries) {
      if (entry.key == 'searchApiConfig.sourceTemplate') {
        final search = effective['searchApiConfig'];
        if (effective['searchMode'] != 'api' || search is! Map) {
          throw const FormatException('详情页地址覆盖需要已有 API 搜索配置');
        }
        search['sourceTemplate'] = entry.value;
      } else {
        effective[entry.key] = entry.value;
      }
    }
    return effective;
  }

  Map<String, dynamic> toJson() => {
        'kind': kind,
        'schemaVersion': schemaVersion,
        'upstream': {'repository': repository, 'commit': commit},
        'baseSha256': baseSha256,
        'baseRule': baseRule,
        'overrides': overrides,
      };

  /// SHA-256 of sorted-key UTF-8 JSON, including normalized schema defaults.
  /// This detects content drift; it is not a signature or a raw-file digest.
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

  static Map<String, dynamic> _object(Object? value) {
    if (value is! Map) throw const FormatException('TV 覆盖字段需要 JSON 对象');
    return Map<String, dynamic>.from(value);
  }

  static Map<String, dynamic> _copy(Map<String, dynamic> value) =>
      Map<String, dynamic>.from(jsonDecode(jsonEncode(value)) as Map);
}
