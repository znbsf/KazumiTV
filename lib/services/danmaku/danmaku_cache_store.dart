import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Public GET data only. Filenames contain a digest, never search text or auth.
class DanmakuCachePolicy {
  const DanmakuCachePolicy(this.kind, this.freshFor);
  final String kind;
  final Duration freshFor;

  static DanmakuCachePolicy? forUri(Uri uri) {
    if (uri.scheme != 'https' ||
        uri.host != 'api.dandanplay.net' ||
        uri.userInfo.isNotEmpty ||
        uri.hasPort) {
      return null;
    }
    if (RegExp(r'^/api/v2/comment/\d+$').hasMatch(uri.path)) {
      return const DanmakuCachePolicy('comments', Duration(hours: 6));
    }
    if (RegExp(r'^/api/v2/bangumi/bgmtv/\d+$').hasMatch(uri.path)) {
      return const DanmakuCachePolicy('bangumi', Duration(days: 7));
    }
    // Episode lists change as a show airs; only the cross-service ID mapping
    // is stable enough for a week.
    if (RegExp(r'^/api/v2/bangumi/\d+$').hasMatch(uri.path)) {
      return const DanmakuCachePolicy('bangumi', Duration(hours: 6));
    }
    if (uri.path == '/api/v2/search/episodes') {
      return const DanmakuCachePolicy('search', Duration(hours: 6));
    }
    return null;
  }

  bool accepts(dynamic value) {
    if (value is! Map ||
        value['success'] == false ||
        (value['errorCode'] != null && value['errorCode'] != 0)) {
      return false;
    }
    return switch (kind) {
      'comments' => value['comments'] is List,
      'search' => value['animes'] is List,
      _ => value['bangumi'] is Map &&
          value['bangumi']['animeId'] is int &&
          value['bangumi']['episodes'] is List,
    };
  }

  bool isEmpty(dynamic value) => switch (kind) {
        'comments' => (value['comments'] as List).isEmpty,
        'search' => (value['animes'] as List).isEmpty,
        _ => value['bangumi']['animeId'] == 0,
      };

  static String keyFor(Uri uri) {
    final keys = uri.queryParametersAll.keys.toList()..sort();
    final canonical = uri.replace(fragment: '', queryParameters: {
      for (final key in keys) key: uri.queryParametersAll[key]!,
    });
    return sha256.convert(utf8.encode(canonical.toString())).toString();
  }
}

/// Owned by a serial background worker. Video cache eviction never reaches here.
class DanmakuCacheStore {
  DanmakuCacheStore(this.root, {DateTime Function()? clock})
      : clock = clock ?? DateTime.now;
  final Directory root;
  final DateTime Function() clock;
  static const maxAge = Duration(days: 30);
  static const maxEntryBytes = 16 * 1024 * 1024;
  static const maxCompressedBytes = 8 * 1024 * 1024;
  static const maxEntries = 4000;
  final Map<String, _Entry> _entries = {};
  bool _initialized = false;
  int limitBytes = 256 * 1024 * 1024;

  File _file(String key) {
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(key)) {
      throw ArgumentError('Invalid cache key');
    }
    return File('${root.path}/$key.json.gz');
  }

  Future<void> initialize() async {
    if (_initialized) return;
    await root.create(recursive: true);
    await for (final file in root.list(followLinks: false)) {
      if (file is! File) continue;
      final name = file.uri.pathSegments.last;
      if (RegExp(r'^[a-f0-9]{64}\.json\.gz\.part$').hasMatch(name)) {
        await file.delete();
        continue;
      }
      if (!RegExp(r'^[a-f0-9]{64}\.json\.gz$').hasMatch(name)) continue;
      final stat = await file.stat();
      final age = clock().difference(stat.modified);
      if (age > maxAge ||
          age < const Duration(minutes: -5) ||
          stat.size > maxCompressedBytes) {
        await file.delete();
        continue;
      }
      _entries[name.substring(0, 64)] =
          _Entry(stat.size, stat.modified, stat.accessed);
    }
    _initialized = true;
    await trim();
  }

  Future<Map<String, dynamic>?> read(String key, Duration freshFor) async {
    await initialize();
    final entry = _entries[key];
    if (entry == null) return null;
    final age = clock().difference(entry.saved);
    if (age > maxAge || age < const Duration(minutes: -5)) {
      await _remove(key);
      return null;
    }
    try {
      // Bounded decompression also protects against a damaged gzip file.
      final file = _file(key);
      if (await file.length() > maxCompressedBytes) {
        throw const FormatException('Oversized cache');
      }
      final output = BytesBuilder(copy: false);
      await for (final chunk in file.openRead().transform(gzip.decoder)) {
        if (output.length + chunk.length > maxEntryBytes) {
          throw const FormatException('Oversized cache');
        }
        output.add(chunk);
      }
      final saved = jsonDecode(utf8.decode(output.takeBytes())) as Map;
      if (saved['version'] != 1 || saved['value'] is! Map) {
        throw const FormatException('Unknown cache format');
      }
      entry.accessed = clock();
      await file.setLastAccessed(entry.accessed);
      final ttl =
          saved['empty'] == true ? const Duration(minutes: 10) : freshFor;
      return {'value': saved['value'], 'fresh': age <= ttl};
    } catch (_) {
      await _remove(key);
      return null;
    }
  }

  Future<void> write(String key, dynamic value, {required bool empty}) async {
    await initialize();
    final raw =
        utf8.encode(jsonEncode({'version': 1, 'empty': empty, 'value': value}));
    if (raw.length > maxEntryBytes) return;
    final bytes = gzip.encode(raw);
    if (bytes.length > maxCompressedBytes || bytes.length > limitBytes) return;
    final file = _file(key);
    final temporary = File('${file.path}.part');
    try {
      await temporary.writeAsBytes(bytes, flush: true);
      await temporary.rename(file.path);
      final now = clock();
      await file.setLastModified(now);
      await file.setLastAccessed(now);
      _entries[key] = _Entry(bytes.length, now, now);
      await trim();
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }

  Future<void> _remove(String key) async {
    _entries.remove(key);
    final file = _file(key);
    if (await file.exists()) await file.delete();
  }

  Future<void> trim() async {
    var used = _entries.values.fold<int>(0, (n, e) => n + e.bytes);
    final keys = _entries.keys.toList()
      ..sort((a, b) => _entries[a]!.accessed.compareTo(_entries[b]!.accessed));
    for (final key in keys) {
      final entry = _entries[key]!;
      if (used <= limitBytes &&
          _entries.length <= maxEntries &&
          clock().difference(entry.saved) <= maxAge) {
        continue;
      }
      used -= entry.bytes;
      await _remove(key);
    }
  }

  Future<void> clear() async {
    await initialize();
    for (final key in _entries.keys.toList()) {
      await _remove(key);
    }
  }

  Future<Map<String, int>> stats() async {
    await initialize();
    await trim();
    return {
      'entries': _entries.length,
      'bytes': _entries.values.fold<int>(0, (n, e) => n + e.bytes)
    };
  }
}

class _Entry {
  _Entry(this.bytes, this.saved, this.accessed);
  final int bytes;
  final DateTime saved;
  DateTime accessed;
}
