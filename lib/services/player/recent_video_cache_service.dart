import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:kazumi/services/network/system_proxy_service.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/services/player/recent_video_cache.dart';
import 'package:kazumi/modules/danmaku/danmaku_module.dart';

class RecentCacheLease {
  RecentCacheLease(this.data, this._service);
  final Map<String, dynamic> data;
  final RecentVideoCacheService _service;
  bool _released = false;
  String get url => data['url'] as String;
  String get id => data['id'] as String;
  bool get offline => data['offline'] == true;
  Map<String, dynamic> get metadata =>
      Map<String, dynamic>.from(data['metadata'] as Map);
  Future<void> release() async {
    if (_released) return;
    _released = true;
    await _service._call('release', {'token': data['token']});
  }
}

/// Only small control messages cross this port. Video bytes, JSON parsing,
/// filesystem scans, quota accounting and loopback HTTP stay in the worker.
class RecentVideoCacheService {
  static final shared = RecentVideoCacheService();
  Future<SendPort>? _worker;

  bool get automaticEnabled =>
      GStorage.getSetting(SettingsKeys.recentVideoCacheEnabled);
  Future<void> setEnabled(bool value) =>
      GStorage.putSetting(SettingsKeys.recentVideoCacheEnabled, value);
  Future<void> setLimitGiB(int value) =>
      GStorage.putSetting(SettingsKeys.recentVideoCacheGiB, value);
  bool get enabled =>
      automaticEnabled && !GStorage.getSetting(SettingsKeys.privateMode);
  int get limitGiB {
    final value = GStorage.getSetting(SettingsKeys.recentVideoCacheGiB);
    return [1, 2, 4, 8].contains(value) ? value : 2;
  }

  Future<SendPort> _start() async {
    final directory = await getApplicationSupportDirectory();
    final ready = ReceivePort();
    final isolate = await Isolate.spawn(
        _cacheWorker,
        [
          ready.sendPort,
          p.join(directory.path, 'recent_video_cache_v1'),
          RootIsolateToken.instance,
        ],
        onError: ready.sendPort);
    try {
      return await ready.first.timeout(const Duration(seconds: 5)) as SendPort;
    } catch (_) {
      isolate.kill(priority: Isolate.immediate);
      _worker = null;
      rethrow;
    } finally {
      ready.close();
    }
  }

  Future<dynamic> _call(String command,
      [Map<String, dynamic> args = const {}]) async {
    final port = await (_worker ??= _start());
    final reply = ReceivePort();
    port.send([reply.sendPort, command, args]);
    try {
      final result = await reply.first as Map;
      if (result['error'] != null) throw StateError(result['error'] as String);
      return result['value'];
    } finally {
      reply.close();
    }
  }

  Future<void> configure() async {
    await _call('configure', {'bytes': limitGiB * 1024 * 1024 * 1024});
  }

  Future<List<Map<String, dynamic>>> list() async {
    await configure();
    final result = await _call('list') as List;
    return result.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<void> clear({String? id}) async => _call('clear', {'id': id});
  Future<void> progress(String id, int position, int duration) async {
    if (GStorage.getSetting(SettingsKeys.privateMode)) return;
    await _call(
        'progress', {'id': id, 'position': position, 'duration': duration});
  }

  Future<void> saveDanmaku(
      String id, List<DanmakuEntry> entries, int bangumiID) async {
    if (entries.isEmpty ||
        entries.length > 100000 ||
        GStorage.getSetting(SettingsKeys.privateMode)) return;
    await _call(
        'saveDanmaku', {'id': id, 'entries': entries, 'bangumiID': bangumiID});
  }

  Future<(List<DanmakuEntry>, int)?> readDanmaku(String id) async {
    final result = await _call('readDanmaku', {'id': id});
    return result as (List<DanmakuEntry>, int)?;
  }

  Future<RecentCacheLease?> openOffline(String id) async {
    try {
      final result = await _call('offline', {'id': id});
      return result == null
          ? null
          : RecentCacheLease(Map<String, dynamic>.from(result as Map), this);
    } catch (_) {
      return null;
    }
  }

  Future<RecentCacheLease?> find(String identity) async =>
      enabled ? openOffline(RecentVideoCache.keyFor(identity)) : null;

  Future<RecentCacheLease?> prepare({
    required String identity,
    required String url,
    required Map<String, String> headers,
    required Map<String, dynamic> metadata,
    required bool hls,
    required bool adBlocker,
  }) async {
    // Experimental path: do not alter proxy or native ad-filter semantics.
    // These modes and non-HLS sources continue to use the existing player.
    if (!enabled ||
        !hls ||
        adBlocker ||
        GStorage.getSetting(SettingsKeys.proxyEnable) ||
        SystemProxyService.isActive) return null;
    try {
      await configure();
      final result = await _call('online', {
        'identity': identity,
        'url': url,
        'headers': headers,
        'metadata': metadata,
      });
      return result == null
          ? null
          : RecentCacheLease(Map<String, dynamic>.from(result as Map), this);
    } catch (_) {
      return null;
    }
  }
}

void _cacheWorker(List<dynamic> startup) {
  final ready = startup[0] as SendPort;
  final token = startup[2] as RootIsolateToken?;
  if (token != null) BackgroundIsolateBinaryMessenger.ensureInitialized(token);
  final cache = RecentVideoCache(Directory(startup[1] as String),
      availableBytes: (path) async {
    try {
      return await const MethodChannel('com.predidit.kazumi/storage')
              .invokeMethod<int>('getAvailableStorage', {'path': path}) ??
          -1;
    } catch (_) {
      // No verified free space means no new writes; existing offline reads work.
      return -1;
    }
  });
  final commands = ReceivePort();
  ready.send(commands.sendPort);
  commands.listen((dynamic message) async {
    final reply = message[0] as SendPort;
    final command = message[1] as String;
    final args = Map<String, dynamic>.from(message[2] as Map);
    try {
      final dynamic value;
      switch (command) {
        case 'configure':
          await cache.configure(args['bytes'] as int);
          value = null;
        case 'list':
          value = await cache.list();
        case 'saveDanmaku':
          final entries = args['entries'] as List<DanmakuEntry>;
          await cache.saveDanmaku(
              args['id'],
              jsonEncode({
                'bangumiID': args['bangumiID'],
                'entries': entries.map((e) => e.toJson()).toList(),
              }));
          value = null;
        case 'readDanmaku':
          final text = await cache.readDanmaku(args['id']);
          if (text == null) {
            value = null;
          } else {
            final data = jsonDecode(text) as Map;
            value = (
              (data['entries'] as List)
                  .map((e) => DanmakuEntry.fromJson(
                      Map<String, dynamic>.from(e as Map)))
                  .toList(),
              data['bangumiID'] as int
            );
          }
        case 'clear':
          await cache.clear(id: args['id'] as String?);
          value = null;
        case 'progress':
          await cache.progress(args['id'], args['position'], args['duration']);
          value = null;
        case 'offline':
          value = await cache.openOffline(args['id'] as String);
        case 'online':
          value = await cache.openOnline(
              identity: args['identity'],
              url: args['url'],
              headers: Map<String, String>.from(args['headers']),
              metadata: Map<String, dynamic>.from(args['metadata']));
        case 'release':
          await cache.release(args['token'] as String);
          value = null;
        default:
          throw ArgumentError('Unknown cache command');
      }
      reply.send({'value': value});
    } catch (_) {
      reply.send({'error': '近期视频缓存操作失败'});
    }
  });
}
