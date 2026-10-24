// QA-only bounded discovery projection. Never fetches pages or media.
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:kazumi/modules/roads/road_module.dart';

String? _label(String text) {
  if (text.trim().isEmpty ||
      text.runes.length > 64 ||
      !RegExp(r'^[\p{L}\p{N} ._()（）【】\[\]、·-]*$', unicode: true)
          .hasMatch(text) ||
      RegExp(r'https?|cookie|authorization|bearer|token|password',
              caseSensitive: false)
          .hasMatch(text)) {
    return null;
  }
  return text;
}

Map<String, Object?> qaSelectionSnapshot(
    List<Road> roads, String Function(String) normalizeUrl,
    {bool tail1 = false}) {
  final output = <Map<String, Object?>>[];
  for (var index = 0; index < roads.length && index < 8; index++) {
    final road = roads[index];
    final episodes = <Map<String, Object?>>[];
    final paired = road.data.length == road.identifier.length;
    if (paired) {
      final indices = <int>[
        for (var i = 0; i < road.data.length && i < 2; i++) i
      ];
      if (tail1 &&
          road.data.isNotEmpty &&
          !indices.contains(road.data.length - 1)) {
        indices.add(road.data.length - 1);
      }
      for (final episode in indices) {
        final label = _label(road.identifier[episode]);
        String? hash;
        try {
          final url = normalizeUrl(road.data[episode]);
          final uri = Uri.tryParse(url);
          if (url.length <= 8192 &&
              uri != null &&
              uri.host.isNotEmpty &&
              {'http', 'https'}.contains(uri.scheme) &&
              uri.userInfo.isEmpty &&
              !uri.hasFragment) {
            hash = sha256.convert(utf8.encode(url)).toString();
          }
        } catch (_) {
          /* Only unsupported metadata; never stringify addresses. */
        }
        episodes.add({
          'episode_index': episode,
          'label': label,
          'episode_page_sha256': hash,
          'binding_available': label != null && hash != null
        });
      }
    }
    output.add({
      'road_index': index,
      'road_label': _label(road.name),
      'episode_count': road.data.length,
      'paired_labels': paired,
      'episodes': episodes
    });
  }
  return {
    'road_count': roads.length,
    'roads_truncated': roads.length > 8,
    'max_roads': 8,
    'max_episodes_per_road': tail1 ? 3 : 2,
    if (tail1) 'ordering': 'unknown',
    'roads': output,
    'parser': 'not_run',
    'media': 'not_run',
    'raw_addresses_saved': false
  };
}

bool qaSelectionTailEnabled(Map<String, dynamic> config) {
  final value = config['selection_tail1'];
  if (value == null && !config.containsKey('selection_tail1')) return false;
  if (value is! bool ||
      (value &&
          (config['selection_only'] != true || config['engine'] != 'app'))) {
    throw const FormatException(
        'Tail discovery requires selection-only App profile');
  }
  return value;
}
