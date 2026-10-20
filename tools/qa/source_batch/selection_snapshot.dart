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
    List<Road> roads, String Function(String) normalizeUrl) {
  final output = <Map<String, Object?>>[];
  for (var index = 0; index < roads.length && index < 8; index++) {
    final road = roads[index];
    final episodes = <Map<String, Object?>>[];
    final paired = road.data.length == road.identifier.length;
    if (paired) {
      for (var episode = 0;
          episode < road.data.length && episode < 2;
          episode++) {
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
    'max_episodes_per_road': 2,
    'roads': output,
    'parser': 'not_run',
    'media': 'not_run',
    'raw_addresses_saved': false
  };
}
