/// Resource URLs live only in the worker session. The persisted manifest
/// contains local names, including encryption keys and initialization maps.
class RecentMediaResource {
  const RecentMediaResource(this.url,
      {this.start, this.length, this.key = false});
  final String url;
  final int? start;
  final int? length;
  final bool key;
  List<Object?> get fingerprint => [url, start, length, key];
}

class RecentHlsManifest {
  RecentHlsManifest(this.playlist, this.resources);
  final String playlist;
  final List<RecentMediaResource> resources;

  static RecentHlsManifest? parse(String text, Uri base, int maxResources) {
    final lines =
        text.trim().split(RegExp(r'\r?\n')).map((l) => l.trim()).toList();
    if (lines.first != '#EXTM3U' || !lines.contains('#EXT-X-ENDLIST'))
      return null;
    final resources = <RecentMediaResource>[];
    final local = <String>[];
    String? pendingRange;
    RecentMediaResource? previousSegment;
    bool needsSegment = false;
    bool encrypted = false;
    bool explicitIv = false;

    String? add(String value,
        {String? range, bool key = false, bool map = false}) {
      final uri = base.resolve(value);
      if (!['http', 'https'].contains(uri.scheme) ||
          uri.path.toLowerCase().endsWith('.m3u8') ||
          resources.length >= maxResources ||
          value.contains(r'{$')) return null;
      int? start;
      int? length;
      if (range != null) {
        final match = RegExp(r'^(\d+)(?:@(\d+))?$').firstMatch(range);
        if (match == null) return null;
        length = int.parse(match[1]!);
        start = match[2] == null ? null : int.parse(match[2]!);
        if (start == null) {
          if (map ||
              previousSegment?.url != uri.toString() ||
              previousSegment?.length == null) return null;
          start = previousSegment!.start! + previousSegment!.length!;
        }
        if (length <= 0 || start < 0) return null;
        // Encrypted byte-range I-frame streams have additional CBC rules.
        if (encrypted && !map) return null;
      }
      final resource = RecentMediaResource(uri.toString(),
          start: start, length: length, key: key);
      // Preserve format hints: renaming an fMP4 init/segment to .ts can make
      // FFmpeg's extension/format checks reject otherwise valid media.
      final extension = uri.path.split('/').last.split('.').last.toLowerCase();
      final suffix = key
          ? 'key'
          : ['ts', 'm4s', 'mp4', 'm4a', 'aac', 'ac3', 'ec3', 'vtt', 'webvtt']
                  .contains(extension)
              ? extension
              : map
                  ? 'mp4'
                  : 'ts';
      final name = 's${resources.length}.$suffix';
      resources.add(resource);
      if (!key && !map) previousSegment = resource;
      return name;
    }

    for (final line in lines) {
      if (line.startsWith('#EXT-X-KEY:') || line.startsWith('#EXT-X-MAP:')) {
        final isKey = line.startsWith('#EXT-X-KEY:');
        final attrs = _attributes(line.substring(line.indexOf(':') + 1));
        if (attrs == null) return null;
        if (isKey) {
          if (attrs['METHOD'] == 'NONE' && attrs.length == 1) {
            encrypted = false;
            local.add(line);
            continue;
          }
          if (attrs['METHOD'] != 'AES-128' ||
              (attrs['KEYFORMAT'] != null &&
                  attrs['KEYFORMAT'] != 'identity') ||
              attrs.keys.any((k) => ![
                    'METHOD',
                    'URI',
                    'IV',
                    'KEYFORMAT',
                    'KEYFORMATVERSIONS'
                  ].contains(k)) ||
              (attrs['KEYFORMATVERSIONS'] != null &&
                  attrs['KEYFORMATVERSIONS'] != '1')) return null;
          explicitIv = attrs.containsKey('IV');
          if (explicitIv &&
              !RegExp(r'^0[xX][a-fA-F0-9]{1,32}$').hasMatch(attrs['IV']!))
            return null;
          encrypted = true;
        } else {
          if (attrs.keys.any((k) => !['URI', 'BYTERANGE'].contains(k)) ||
              (encrypted && !explicitIv)) return null;
        }
        final uri = attrs['URI'];
        if (uri == null) return null;
        final name =
            add(uri, range: attrs['BYTERANGE'], key: isKey, map: !isKey);
        if (name == null) return null;
        local.add(isKey
            ? '#EXT-X-KEY:METHOD=AES-128,URI="$name"${explicitIv ? ',IV=${attrs['IV']}' : ''}'
            : '#EXT-X-MAP:URI="$name"');
      } else if (line.startsWith('#EXT-X-BYTERANGE:')) {
        if (pendingRange != null) return null;
        pendingRange = line.substring('#EXT-X-BYTERANGE:'.length);
      } else if (line.isNotEmpty && !line.startsWith('#')) {
        if (!needsSegment) return null;
        final name = add(line, range: pendingRange);
        if (name == null) return null;
        local.add(name);
        pendingRange = null;
        needsSegment = false;
      } else {
        // Admit only media tags whose semantics survive local URI rewriting.
        if (line.startsWith('#EXT') &&
            ![
              '#EXTM3U',
              '#EXTINF',
              '#EXT-X-VERSION',
              '#EXT-X-TARGETDURATION',
              '#EXT-X-MEDIA-SEQUENCE',
              '#EXT-X-DISCONTINUITY-SEQUENCE',
              '#EXT-X-DISCONTINUITY',
              '#EXT-X-ENDLIST',
              '#EXT-X-PLAYLIST-TYPE',
              '#EXT-X-PROGRAM-DATE-TIME',
              '#EXT-X-INDEPENDENT-SEGMENTS',
            ].contains(line.split(':').first)) return null;
        if (line == '#EXT-X-PLAYLIST-TYPE:EVENT' || line.contains('URI='))
          return null;
        if (line.startsWith('#EXTINF:')) {
          if (needsSegment) return null;
          needsSegment = true;
        }
        local.add(line);
      }
    }
    if (previousSegment == null || needsSegment || pendingRange != null)
      return null;
    return RecentHlsManifest('${local.join('\n')}\n', resources);
  }

  static Map<String, String>? _attributes(String value) {
    final attrs = <String, String>{};
    final pattern = RegExp(r'([A-Z0-9-]+)=(?:"([^"]*)"|([^,]+))(?:,|$)');
    var offset = 0;
    for (final match in pattern.allMatches(value)) {
      if (match.start != offset || attrs.containsKey(match[1])) return null;
      attrs[match[1]!] = match[2] ?? match[3]!;
      offset = match.end;
    }
    return offset == value.length ? attrs : null;
  }
}
