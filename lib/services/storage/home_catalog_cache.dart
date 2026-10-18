import 'dart:convert';
import 'dart:io';

import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:path_provider/path_provider.dart';

class HomeCatalogSnapshot {
  HomeCatalogSnapshot(this.items, this.updatedAt);
  final List<BangumiItem> items;
  final DateTime updatedAt;
  bool get stale =>
      DateTime.now().difference(updatedAt) > const Duration(hours: 6);
}

/// Public home metadata only. Images use the existing bounded image cache;
/// request headers, account state and signed URLs are never serialized here.
class HomeCatalogCache {
  HomeCatalogCache({this.directory});
  final Directory? directory;
  static Future<void> _pendingWrites = Future<void>.value();
  static Future<void> flush() => _pendingWrites;
  static const version = 1;
  static const maxItems = 96;
  static const maxBytes = 1024 * 1024;
  static const retention = Duration(days: 30);

  Future<File> _file(bool mirror) async {
    final dir = directory ?? await getApplicationSupportDirectory();
    return File(
      '${dir.path}/home-catalog-${mirror ? 'mirror' : 'direct'}.json',
    );
  }

  Future<HomeCatalogSnapshot?> read(bool mirror) async {
    await _pendingWrites;
    try {
      final file = await _file(mirror);
      if (!await file.exists()) return null;
      if (await file.length() > maxBytes) throw const FormatException();
      final data = jsonDecode(await file.readAsString()) as Map;
      // Unknown schemas are disposable caches, never user data migrations.
      if (data['version'] != version) throw const FormatException();
      final updated = DateTime.parse(data['updatedAt'] as String);
      final age = DateTime.now().difference(updated);
      if (age.isNegative || age > retention) throw const FormatException();
      final raw = data['items'] as List;
      if (raw.isEmpty || raw.length > maxItems) throw const FormatException();
      final items = raw
          .map((e) => BangumiItem.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
      if (items.any((e) => e.id <= 0)) throw const FormatException();
      return HomeCatalogSnapshot(items, updated);
    } catch (_) {
      try {
        final file = await _file(mirror);
        if (await file.exists()) await file.delete();
      } catch (_) {}
      return null;
    }
  }

  Future<void> write(bool mirror, List<BangumiItem> items, DateTime updated) {
    final snapshot = List<BangumiItem>.of(items);
    return _pendingWrites =
        _pendingWrites.then((_) => _write(mirror, snapshot, updated));
  }

  Future<void> _write(
      bool mirror, List<BangumiItem> items, DateTime updated) async {
    if (items.isEmpty) return;
    try {
      final data = jsonEncode({
        'version': version,
        'updatedAt': updated.toUtc().toIso8601String(),
        'items': items
            .take(maxItems)
            .map(
              (e) => {
                'id': e.id,
                'type': e.type,
                'name': e.name,
                'name_cn': e.nameCn,
                'date': e.airDate,
                'rating': {
                  'rank': e.rank,
                  'score': e.ratingScore,
                  'total': e.votes,
                },
                'images': Map.fromEntries(
                  e.images.entries.where((entry) {
                    final uri = Uri.tryParse(entry.value);
                    return uri != null &&
                        (uri.scheme == 'https' || uri.scheme == 'http') &&
                        uri.userInfo.isEmpty &&
                        !uri.hasQuery &&
                        !uri.hasFragment;
                  }),
                ),
              },
            )
            .toList(),
      });
      if (utf8.encode(data).length > maxBytes) return;
      final file = await _file(mirror);
      await file.parent.create(recursive: true);
      final temporary = File('${file.path}.tmp');
      await temporary.writeAsString(data, flush: true);
      await temporary.rename(file.path);
    } catch (_) {
      // Disk full/unavailable cache must not turn successful network data into failure.
    }
  }
}
