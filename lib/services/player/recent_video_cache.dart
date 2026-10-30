import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'package:kazumi/utils/async_serial_queue.dart';
import 'package:kazumi/services/player/recent_hls_manifest.dart';

/// A deliberately conservative VOD cache. Only plain, finite HLS playlists are
/// admitted. Unsupported manifests leave the original player path untouched.
/// No upstream URLs, request headers or credentials are persisted.
class RecentVideoCache {
  RecentVideoCache(this.root, {required this.availableBytes});

  final Directory root;
  final Future<int> Function(String path) availableBytes;
  static const reserveBytes = 1024 * 1024 * 1024;
  static const maxManifestBytes = 512 * 1024;
  // Reserve two metadata generations, including interrupted atomic writes.
  static const entryOverhead = 2 * maxManifestBytes;
  static const maxDanmakuBytes = 8 * 1024 * 1024;
  static const maxEntries = 128;
  static const maxSegments = 4096;
  final _queue = AsyncSerialQueue();
  final _entries = <String, _Entry>{};
  final _sessions = <String, _Session>{};
  HttpServer? _server;
  Future<void>? _initializing;
  int _limit = 2 * 1024 * 1024 * 1024;
  int _used = 0;

  static String keyFor(String identity) =>
      sha256.convert(utf8.encode(identity)).toString();

  File _file(String id, String name) => File(p.join(root.path, id, name));
  bool _active(String id) => _sessions.values.any((s) => s.entry.id == id);

  Future<void> initialize() => _initializing ??= _queue.run(() async {
        await root.create(recursive: true);
        await for (final dir in root.list(followLinks: false)) {
          if (dir is! Directory ||
              !RegExp(r'^[a-f0-9]{64}$').hasMatch(p.basename(dir.path))) {
            continue;
          }
          final id = p.basename(dir.path);
          try {
            final metadata = _file(id, 'entry.json');
            if (await metadata.length() > maxManifestBytes) {
              throw const FormatException('metadata too large');
            }
            final entry =
                _Entry.fromJson(id, jsonDecode(await metadata.readAsString()));
            // Reconcile once on worker startup, never once per UI frame/chunk.
            await for (final file in dir.list(followLinks: false)) {
              final name = p.basename(file.path);
              if (file is! File) continue;
              if (name.endsWith('.part') || name == 'entry.next') {
                await file.delete();
              } else if (RegExp(r'^s\d+\.ts$').hasMatch(name)) {
                final index = int.parse(name.substring(1, name.length - 3));
                if (index >= entry.lengths.length ||
                    entry.lengths[index] != await file.length() ||
                    entry.lengths[index] == 0) {
                  await file.delete();
                  if (index < entry.lengths.length) entry.lengths[index] = 0;
                }
              }
            }
            await _validateFiles(entry);
            final comments = _file(id, 'danmaku.json');
            if (!await comments.exists() ||
                await comments.length() != entry.danmakuBytes) {
              entry.danmakuBytes = 0;
              if (await comments.exists()) await comments.delete();
            }
            _entries[id] = entry;
            _used += entry.bytes;
          } catch (_) {
            // Only our hash-named child, never symlinks or manual downloads.
            await dir.delete(recursive: true);
          }
        }
      });

  Future<void> configure(int bytes) async {
    await initialize();
    await _queue.run(() async {
      _limit = max(0, bytes);
      await _makeRoom(0);
    });
  }

  Future<List<Map<String, dynamic>>> list() async {
    await initialize();
    return _queue.run(() async {
      final entries = _entries.values.toList()
        ..sort((a, b) => b.accessed.compareTo(a.accessed));
      return entries.map((e) => e.summary(active: _active(e.id))).toList();
    });
  }

  Future<void> clear({String? id}) async {
    await initialize();
    await _queue.run(() async {
      for (final entry in _entries.values.toList()) {
        if ((id == null || entry.id == id) && !_active(entry.id)) {
          await _remove(entry);
        }
      }
    });
  }

  Future<void> progress(String id, int position, int duration) async {
    await initialize();
    await _queue.run(() async {
      final entry = _entries[id];
      if (entry == null) return;
      entry.metadata['position'] = max(0, position);
      entry.metadata['duration'] = max(0, duration);
      await _save(entry);
    });
  }

  Future<void> saveDanmaku(String id, String json) async {
    final bytes = utf8.encode(json);
    if (bytes.length > maxDanmakuBytes) return;
    await initialize();
    await _queue.run(() async {
      final entry = _entries[id];
      if (entry == null) return;
      final free = await availableBytes(root.path);
      if (free < reserveBytes + bytes.length) return;
      // Protect this entry while making room for the replacement file.
      if (!await _makeRoom(bytes.length, protectedId: id)) return;
      final next = _file(id, 'danmaku.part');
      try {
        await next.writeAsBytes(bytes);
        await next.rename(_file(id, 'danmaku.json').path);
        _used += bytes.length - entry.danmakuBytes;
        entry.danmakuBytes = bytes.length;
        entry.metadata['danmakuUpdated'] =
            DateTime.now().millisecondsSinceEpoch;
        await _save(entry);
      } finally {
        if (await next.exists()) await next.delete();
      }
    });
  }

  Future<String?> readDanmaku(String id) async {
    await initialize();
    return _queue.run(() async {
      final entry = _entries[id];
      if (entry == null || entry.danmakuBytes == 0) return null;
      final file = _file(id, 'danmaku.json');
      if (await file.length() > maxDanmakuBytes) return null;
      return file.readAsString();
    });
  }

  Future<Map<String, dynamic>?> openOffline(String id) async {
    await initialize();
    return _queue.run(() async {
      final entry = _entries[id];
      if (entry == null) return null;
      await _validateFiles(entry);
      if (!entry.complete) return null;
      return _lease(entry, null, const [], const {});
    });
  }

  Future<Map<String, dynamic>?> openOnline({
    required String identity,
    required String url,
    required Map<String, String> headers,
    required Map<String, dynamic> metadata,
    bool hls = true,
    String? proxy,
  }) async {
    await initialize();
    final id = keyFor(identity);
    final cached = await openOffline(id);
    if (cached != null) return cached;
    final client = HttpClient()
      ..autoUncompress = false
      ..connectionTimeout = const Duration(seconds: 5);
    if (proxy != null) client.findProxy = (_) => proxy;
    try {
      // Preparation has one absolute deadline. Closing the client cancels I/O.
      final parsed = await (hls
              ? _readPlaylist(client, Uri.parse(url), headers)
              : _readMp4(client, Uri.parse(url), headers))
          .timeout(const Duration(seconds: 6), onTimeout: () {
        client.close(force: true);
        throw TimeoutException('cache preparation');
      });
      if (parsed == null) return null;
      return await _queue.run(() async {
        if (_active(id)) return null;
        final free = await availableBytes(root.path);
        if (free < reserveBytes || _limit <= 0) return null;
        final fingerprint = keyFor(jsonEncode([
          parsed.playlist,
          parsed.resources.map((r) => r.fingerprint).toList()
        ]));
        var entry = _entries[id];
        if (entry != null && entry.fingerprint != fingerprint) {
          await _remove(entry);
          entry = null;
        }
        if (entry == null) {
          if (!await _makeRoom(entryOverhead, newEntry: true)) return null;
          entry = _Entry(id, fingerprint, parsed.playlist,
              List.filled(parsed.resources.length, 0), metadata);
          await Directory(p.join(root.path, id)).create();
          _entries[id] = entry;
          _used += entryOverhead;
          await _save(entry);
        }
        // This client moves to the session; it is closed on release.
        return _lease(entry, client, parsed.resources, headers);
      });
    } catch (_) {
      // A cache probe must never prevent normal streaming.
      return null;
    } finally {
      if (!_sessions.values.any((s) => identical(s.client, client))) {
        client.close(force: true);
      }
    }
  }

  Future<Map<String, dynamic>> _lease(_Entry entry, HttpClient? client,
      List<RecentMediaResource> urls, Map<String, String> headers) async {
    _server ??= await HttpServer.bind(InternetAddress.loopbackIPv4, 0)
      ..listen(_serve);
    final random = Random.secure();
    final token = List.generate(24, (_) => random.nextInt(256))
        .map((v) => v.toRadixString(16).padLeft(2, '0'))
        .join();
    final session = _Session(token, entry, client, urls, headers);
    _sessions[token] = session;
    entry.accessed = DateTime.now().millisecondsSinceEpoch;
    try {
      await _save(entry);
    } catch (_) {
      // Read-only playback may still work even if metadata can't be refreshed.
    }
    return {
      ...entry.summary(active: true),
      'token': token,
      'url':
          'http://127.0.0.1:${_server!.port}/$token/${entry.mp4 ? 'media.mp4' : 'playlist.m3u8'}',
      'offline': client == null,
    };
  }

  Future<void> release(String token) async {
    final session = _sessions[token];
    if (session == null || session.closed) return;
    session.closed = true;
    session.client?.close(force: true);
    for (final request in session.requests.toList()) {
      try {
        final socket = await request.response.detachSocket();
        socket.destroy();
      } catch (_) {}
    }
    await Future.wait(session.pending.values.toList());
    await _queue.run(() async {
      _sessions.remove(token);
      await _makeRoom(0);
      if (_sessions.isEmpty) {
        await _server?.close(force: true);
        _server = null;
      }
    });
  }

  Future<void> close() async {
    for (final token in _sessions.keys.toList()) {
      await release(token);
    }
  }

  Future<void> _serve(HttpRequest request) async {
    _Session? session;
    try {
      final parts = request.uri.pathSegments;
      if ((request.method != 'GET' && request.method != 'HEAD') ||
          parts.length != 2 ||
          request.uri.hasQuery) {
        request.response.statusCode = HttpStatus.notFound;
        return;
      }
      session = _sessions[parts[0]];
      if (session == null || session.closed) {
        request.response.statusCode = HttpStatus.notFound;
        return;
      }
      // Do not serve media to browser-origin fetches or expose upstream URLs.
      if (request.headers.value('origin') != null) {
        request.response.statusCode = HttpStatus.forbidden;
        return;
      }
      session.requests.add(request);
      request.response.headers.set('Cache-Control', 'no-store');
      if (parts[1] == 'playlist.m3u8' && !session.entry.mp4) {
        final data = utf8.encode(session.entry.playlist);
        request.response.headers.contentType =
            ContentType('application', 'vnd.apple.mpegurl');
        request.response.contentLength = data.length;
        if (request.method == 'GET') request.response.add(data);
        return;
      }
      final match =
          RegExp(r'^s(\d+)\.(?:ts|key|m4s|mp4|m4a|aac|ac3|ec3|vtt|webvtt)$')
              .firstMatch(parts[1]);
      final index = session.entry.mp4 && parts[1] == 'media.mp4'
          ? 0
          : match == null
              ? -1
              : int.parse(match[1]!);
      if (index < 0 || index >= session.entry.lengths.length) {
        request.response.statusCode = HttpStatus.notFound;
        return;
      }
      // A concurrent request for the same segment waits for the original tee.
      // There is never a second background full-file download.
      final previous = session.pending[index];
      final done = Completer<void>();
      session.pending[index] = done.future;
      try {
        await previous;
        if (session.closed) return;
        final file = _file(session.entry.id, 's$index.ts');
        if (session.entry.lengths[index] > 0 && await file.exists()) {
          await _serveFile(request, file, mp4: session.entry.mp4);
          return;
        }
        if (session.client == null) {
          request.response.statusCode = HttpStatus.gone;
          return;
        }
        await _relay(request, session, index);
      } finally {
        if (identical(session.pending[index], done.future)) {
          session.pending.remove(index);
        }
        done.complete();
      }
    } catch (_) {
      try {
        request.response.statusCode = HttpStatus.badGateway;
      } catch (_) {}
    } finally {
      session?.requests.remove(request);
      try {
        await request.response.close();
      } catch (_) {}
    }
  }

  Future<void> _serveFile(HttpRequest request, File file,
      {bool mp4 = false}) async {
    final length = await file.length();
    var start = 0;
    var end = length - 1;
    final range = request.headers.value('range');
    if (range != null) {
      final match = RegExp(r'^bytes=(\d*)-(\d*)$').firstMatch(range);
      if (match == null || (match[1]!.isEmpty && match[2]!.isEmpty)) {
        request.response.statusCode = 416;
        return;
      }
      if (match[1]!.isEmpty) {
        start = max(0, length - int.parse(match[2]!));
      } else {
        start = int.parse(match[1]!);
        if (match[2]!.isNotEmpty) end = min(end, int.parse(match[2]!));
      }
      if (start > end || start >= length) {
        request.response.statusCode = 416;
        request.response.headers.set('Content-Range', 'bytes */$length');
        return;
      }
      request.response.statusCode = 206;
      request.response.headers
          .set('Content-Range', 'bytes $start-$end/$length');
    }
    request.response.headers.set('Accept-Ranges', 'bytes');
    request.response.headers.contentType =
        mp4 ? ContentType('video', 'mp4') : ContentType.binary;
    request.response.contentLength = end - start + 1;
    if (request.method != 'HEAD') {
      await request.response.addStream(file.openRead(start, end + 1));
    }
  }

  Future<void> _relay(HttpRequest request, _Session session, int index) async {
    final range = request.headers.value('range');
    final resource = session.urls[index];
    var resourceStart = 0;
    var resourceEnd = (resource.length ?? 1) - 1;
    if (resource.length != null && range != null) {
      final parsed = RegExp(r'^bytes=(\d*)-(\d*)$').firstMatch(range);
      if (parsed == null || (parsed[1]!.isEmpty && parsed[2]!.isEmpty)) {
        request.response.statusCode = 416;
        return;
      }
      if (parsed[1]!.isEmpty) {
        resourceStart = max(0, resource.length! - int.parse(parsed[2]!));
      } else {
        resourceStart = int.parse(parsed[1]!);
        if (parsed[2]!.isNotEmpty)
          resourceEnd = min(resourceEnd, int.parse(parsed[2]!));
      }
      if (resourceStart > resourceEnd || resourceStart >= resource.length!) {
        request.response.statusCode = 416;
        request.response.headers
            .set('Content-Range', 'bytes */${resource.length}');
        return;
      }
    }
    final upstreamRange = resource.length == null
        ? range
        : 'bytes=${resource.start! + resourceStart}-${resource.start! + resourceEnd}';
    final headers = {
      for (final h in session.headers.entries)
        if (h.key.toLowerCase() != 'range') h.key: h.value,
      if (upstreamRange != null) 'Range': upstreamRange,
    };
    final result = await _get(session.client!, Uri.parse(resource.url), headers,
        method: request.method);
    final upstream = result.$1;
    if (resource.length != null) {
      final match = RegExp(r'^bytes (\d+)-(\d+)/(\d+)$')
          .firstMatch(upstream.headers.value('content-range') ?? '');
      if (upstream.statusCode != 206 ||
          match == null ||
          int.parse(match[1]!) != resource.start! + resourceStart ||
          int.parse(match[2]!) != resource.start! + resourceEnd ||
          int.parse(match[3]!) <= int.parse(match[2]!)) {
        await upstream.listen(null).cancel();
        throw const HttpException('invalid source byte range');
      }
    }
    request.response.statusCode = upstream.statusCode;
    for (final name in [
      'content-type',
      'content-length',
      'content-range',
      'content-encoding',
      'accept-ranges'
    ]) {
      final value = upstream.headers.value(name);
      if (value != null) request.response.headers.set(name, value);
    }
    if (resource.length != null) {
      request.response.statusCode = range == null ? 200 : 206;
      request.response.headers.removeAll('content-range');
      if (range != null)
        request.response.headers.set('Content-Range',
            'bytes $resourceStart-$resourceEnd/${resource.length}');
    }
    // Only full, successfully terminated responses become durable segments.
    final contentRange = RegExp(r'^bytes 0-(\d+)/(\d+)$')
        .firstMatch(upstream.headers.value('content-range') ?? '');
    final fullResponse = (resource.length != null &&
            resourceStart == 0 &&
            resourceEnd == resource.length! - 1) ||
        upstream.statusCode == 200 ||
        (upstream.statusCode == 206 &&
            contentRange != null &&
            int.parse(contentRange[1]!) + 1 == int.parse(contentRange[2]!));
    var saving = request.method == 'GET' &&
        fullResponse &&
        (!session.entry.mp4 ||
            ['video/mp4', 'application/octet-stream']
                .contains(upstream.headers.contentType?.mimeType)) &&
        (upstream.headers.value('content-encoding') == null ||
            upstream.headers.value('content-encoding') == 'identity') &&
        !session.writeDisabled;
    RandomAccessFile? output;
    final partial = _file(session.entry.id, 's$index.ts.part');
    var reserved = 0;
    var received = 0;
    var nextSpaceCheck = 8 * 1024 * 1024;
    var committed = false;
    try {
      if (saving) {
        final free = await availableBytes(root.path);
        saving = free >= reserveBytes + max(0, upstream.contentLength);
        if (saving) {
          try {
            output = await partial.open(mode: FileMode.write);
          } catch (_) {
            saving = false;
          }
        }
        if (!saving) session.writeDisabled = true;
      }
      await for (final chunk in upstream.timeout(const Duration(seconds: 15))) {
        if (session.closed) break;
        received += chunk.length;
        if (saving && received >= nextSpaceCheck) {
          saving =
              await availableBytes(root.path) >= reserveBytes + 8 * 1024 * 1024;
          nextSpaceCheck = received + 8 * 1024 * 1024;
          if (!saving) session.writeDisabled = true;
        }
        // Split unusually large chunks too; one bounded write outstanding.
        for (var offset = 0; offset < chunk.length; offset += 65536) {
          final bytes = chunk is Uint8List
              ? Uint8List.sublistView(
                  chunk, offset, min(offset + 65536, chunk.length))
              : chunk.sublist(offset, min(offset + 65536, chunk.length));
          if (saving) {
            var granted = false;
            try {
              granted = await _queue.run(() async {
                if (!await _makeRoom(bytes.length)) return false;
                _used += bytes.length;
                return true;
              });
            } catch (_) {/* Cache I/O errors must not abort playback. */}
            if (granted) {
              reserved += bytes.length;
              try {
                await output!.writeFrom(bytes);
              } catch (_) {
                saving = false;
              }
            } else {
              saving = false;
            }
            if (!saving) session.writeDisabled = true;
          }
          request.response.add(bytes);
          await request.response.flush();
        }
      }
      await output?.close();
      output = null;
      if (saving &&
          !session.closed &&
          received > 0 &&
          (!resource.key || received == 16) &&
          (resource.length == null || received == resource.length) &&
          (upstream.contentLength < 0 || received == upstream.contentLength)) {
        await _queue.run(() async {
          await partial.rename(_file(session.entry.id, 's$index.ts').path);
          session.entry.lengths[index] = received;
          try {
            await _save(session.entry);
            committed = true;
          } catch (_) {
            session.entry.lengths[index] = 0;
            await _file(session.entry.id, 's$index.ts').delete();
          }
        });
      }
    } finally {
      await output?.close();
      if (!committed) {
        try {
          if (await partial.exists()) await partial.delete();
        } finally {
          await _queue.run(() async {
            _used -= reserved;
          });
        }
      }
    }
  }

  Future<bool> _makeRoom(int additional,
      {bool newEntry = false, String? protectedId}) async {
    if (_used + additional <= _limit &&
        _entries.length + (newEntry ? 1 : 0) <= maxEntries) return true;
    final candidates = _entries.values
        .where((e) => !_active(e.id) && e.id != protectedId)
        .toList()
      ..sort((a, b) => a.accessed.compareTo(b.accessed));
    while (_used + additional > _limit ||
        _entries.length + (newEntry ? 1 : 0) > maxEntries) {
      if (candidates.isEmpty) return false;
      await _remove(candidates.removeAt(0));
    }
    return true;
  }

  Future<void> _remove(_Entry entry) async {
    await Directory(p.join(root.path, entry.id)).delete(recursive: true);
    _entries.remove(entry.id);
    _used -= entry.bytes;
  }

  Future<void> _save(_Entry entry) async {
    final next = _file(entry.id, 'entry.next');
    final bytes = utf8.encode(jsonEncode(entry.toJson()));
    if (bytes.length > maxManifestBytes)
      throw const FormatException('metadata too large');
    await next.writeAsBytes(bytes);
    await next.rename(_file(entry.id, 'entry.json').path);
  }

  Future<void> _validateFiles(_Entry entry) async {
    for (var i = 0; i < entry.lengths.length; i++) {
      if (entry.lengths[i] <= 0) continue;
      final file = _file(entry.id, 's$i.ts');
      if (!await file.exists() || await file.length() != entry.lengths[i]) {
        if (_entries.containsKey(entry.id)) _used -= entry.lengths[i];
        entry.lengths[i] = 0;
      }
    }
  }

  Future<RecentHlsManifest?> _readMp4(
      HttpClient client, Uri uri, Map<String, String> headers) async {
    final (response, finalUri) =
        await _get(client, uri, headers, method: 'HEAD');
    final mime = response.headers.contentType?.mimeType;
    if (response.statusCode != 200 ||
        response.contentLength <= 0 ||
        !(mime == 'video/mp4' ||
            (mime == 'application/octet-stream' &&
                finalUri.path.toLowerCase().endsWith('.mp4')))) return null;
    await response.drain<void>();
    return RecentHlsManifest('', [RecentMediaResource(finalUri.toString())]);
  }

  Future<RecentHlsManifest?> _readPlaylist(
      HttpClient client, Uri uri, Map<String, String> headers,
      [int depth = 0]) async {
    if (depth > 2) return null;
    final (response, finalUri) = await _get(client, uri, headers);
    if (response.statusCode != 200) return null;
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in response) {
      if (bytes.length + chunk.length > maxManifestBytes) return null;
      bytes.add(chunk);
    }
    final content = utf8.decode(bytes.takeBytes()).trim();
    if (!content.startsWith('#EXTM3U')) return null;
    final lines = content.split(RegExp(r'\r?\n')).map((l) => l.trim()).toList();
    if (lines.any((l) => l.startsWith('#EXT-X-STREAM-INF:'))) {
      if (lines.any((l) =>
          l.contains('URI=') ||
          l.contains('AUDIO=') ||
          l.contains('VIDEO=') ||
          l.contains('SUBTITLES=') ||
          l.startsWith('#EXT-X-DEFINE'))) return null;
      // A single rendition preserves the source's track/quality selection.
      final variants =
          lines.where((l) => l.isNotEmpty && !l.startsWith('#')).toList();
      if (variants.length != 1) return null;
      return _readPlaylist(
          client, finalUri.resolve(variants.single), headers, depth + 1);
    }
    return RecentHlsManifest.parse(content, finalUri, maxSegments);
  }

  Future<(HttpClientResponse, Uri)> _get(
      HttpClient client, Uri uri, Map<String, String> headers,
      {String method = 'GET'}) async {
    var safeHeaders = Map<String, String>.from(headers);
    for (var redirect = 0; redirect <= 5; redirect++) {
      if (uri.scheme != 'http' && uri.scheme != 'https') {
        throw const FormatException('unsupported scheme');
      }
      final request = await client.openUrl(method, uri);
      request.followRedirects = false;
      safeHeaders.forEach((name, value) {
        if (!['host', 'connection', 'content-length', 'accept-encoding']
            .contains(name.toLowerCase())) request.headers.set(name, value);
      });
      request.headers.set('Accept-Encoding', 'identity');
      final response = await request.close();
      if (![301, 302, 303, 307, 308].contains(response.statusCode)) {
        return (response, uri);
      }
      final location = response.headers.value('location');
      if (location == null) throw const FormatException('missing redirect');
      final next = uri.resolve(location);
      if (next.origin != uri.origin) {
        safeHeaders.removeWhere(
            (k, _) => ['authorization', 'cookie'].contains(k.toLowerCase()));
      }
      await response.drain<void>();
      uri = next;
    }
    throw const HttpException('redirect limit');
  }
}

class _Entry {
  _Entry(this.id, this.fingerprint, this.playlist, this.lengths,
      Map<String, dynamic> metadata)
      : metadata = Map.of(metadata);
  final String id;
  final String fingerprint;
  final String playlist;
  bool get mp4 => playlist.isEmpty;
  final List<int> lengths;
  final Map<String, dynamic> metadata;
  int accessed = DateTime.now().millisecondsSinceEpoch;
  int danmakuBytes = 0;
  int get bytes =>
      lengths.fold(0, (a, b) => a + b) +
      RecentVideoCache.entryOverhead +
      danmakuBytes;
  bool get complete => lengths.isNotEmpty && lengths.every((v) => v > 0);

  factory _Entry.fromJson(String id, dynamic json) {
    if (json['version'] != 1) throw const FormatException('cache version');
    final lengths = List<int>.from(json['lengths']);
    if (lengths.isEmpty ||
        lengths.length > RecentVideoCache.maxSegments ||
        lengths.any((v) => v < 0)) throw const FormatException('segments');
    final playlist = json['playlist'] as String;
    if (playlist.isNotEmpty) {
      final parsed = RecentHlsManifest.parse(playlist,
          Uri.parse('http://cache.invalid/'), RecentVideoCache.maxSegments);
      if (parsed == null ||
          parsed.resources.any((r) =>
              !RegExp(r'^http://cache\.invalid/s\d+\.(?:ts|key|m4s|mp4|m4a|aac|ac3|ec3|vtt|webvtt)$')
                  .hasMatch(r.url) ||
              r.length != null))
        throw const FormatException('nonlocal resources');
    }
    final files = playlist
        .split('\n')
        .where((l) => l.isNotEmpty && !l.startsWith('#'))
        .toList();
    files.addAll(
        RegExp(r'URI="([^"]+)"').allMatches(playlist).map((m) => m[1]!));
    final expected = List.generate(lengths.length, (i) => 's$i').toSet();
    final indices = files.map((name) => name.split('.').first).toSet();
    if (playlist.isEmpty
        ? lengths.length != 1
        : files.length != lengths.length ||
            indices.difference(expected).isNotEmpty ||
            expected.difference(indices).isNotEmpty ||
            !playlist.contains('#EXT-X-ENDLIST')) {
      throw const FormatException('nonlocal playlist');
    }
    return _Entry(id, json['fingerprint'], playlist, lengths,
        Map<String, dynamic>.from(json['metadata']))
      ..accessed = json['accessed'] as int
      ..danmakuBytes = (json['danmakuBytes'] as int? ?? 0)
          .clamp(0, RecentVideoCache.maxDanmakuBytes);
  }

  Map<String, dynamic> toJson() => {
        'version': 1,
        'fingerprint': fingerprint,
        'playlist': playlist,
        'lengths': lengths,
        'metadata': metadata,
        'accessed': accessed,
        'danmakuBytes': danmakuBytes,
      };
  Map<String, dynamic> summary({required bool active}) => {
        'id': id,
        'metadata': Map<String, dynamic>.from(metadata),
        'bytes': bytes,
        'complete': complete,
        'saved': lengths.where((v) => v > 0).length,
        'total': lengths.length,
        'active': active,
      };
}

class _Session {
  _Session(this.token, this.entry, this.client, this.urls, this.headers);
  final String token;
  final _Entry entry;
  final HttpClient? client;
  final List<RecentMediaResource> urls;
  final Map<String, String> headers;
  final requests = <HttpRequest>{};
  final pending = <int, Future<void>>{};
  bool closed = false;
  bool writeDisabled = false;
}
