import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:kazumi/request/core/network_exception.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'danmaku_cache_store.dart';

/// Shared by automatic matching, manual search and downloaded episode requests.
class DanmakuCacheService {
  DanmakuCacheService(
      {Future<Directory> Function()? directory,
      bool Function()? enabled,
      bool Function()? privateMode,
      int Function()? limitMiB,
      DateTime Function()? clock})
      : _directory = directory ?? getApplicationSupportDirectory,
        _enabled = enabled ??
            (() => GStorage.getSetting(SettingsKeys.danmakuCacheEnabled)),
        _privateMode = privateMode ??
            (() => GStorage.getSetting(SettingsKeys.privateMode)),
        _limitMiB = limitMiB ??
            (() => GStorage.getSetting(SettingsKeys.danmakuCacheMiB)),
        _clock = clock ?? DateTime.now;

  static final shared = DanmakuCacheService();
  final Future<Directory> Function() _directory;
  final bool Function() _enabled;
  final bool Function() _privateMode;
  final int Function() _limitMiB;
  final DateTime Function() _clock;
  final Map<String, Future<dynamic>> _pending = {};
  Future<SendPort>? _worker;
  Isolate? _isolate;
  DateTime? _cooldownUntil;
  NetworkException? _rateLimitError;
  int _epoch = 0;

  Future<SendPort> _start() async {
    final root = await _directory();
    final ready = ReceivePort();
    try {
      _isolate = await Isolate.spawn(
          _runCache, [ready.sendPort, '${root.path}/danmaku_cache_v1']);
      return await ready.first.timeout(const Duration(seconds: 5)) as SendPort;
    } catch (_) {
      _isolate?.kill(priority: Isolate.immediate);
      _isolate = null;
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
    try {
      port.send([
        reply.sendPort,
        command,
        {
          ...args,
          'now': _clock().millisecondsSinceEpoch,
          'limit': _limitMiB().clamp(64, 1024) * 1024 * 1024
        }
      ]);
      final result =
          await reply.first.timeout(const Duration(seconds: 10)) as Map;
      if (result['error'] != null) throw StateError(result['error'] as String);
      return result['value'];
    } finally {
      reply.close();
    }
  }

  Future<Map<String, int>> stats() async =>
      Map<String, int>.from(await _call('stats') as Map);

  Future<void> clear() async {
    _epoch++;
    _pending.clear();
    await _call('clear');
  }

  Future<void> resize() async => _call('trim');

  Future<void> close() async {
    _epoch++;
    _pending.clear();
    if (_worker != null) {
      try {
        await _worker;
      } catch (_) {}
    }
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _worker = null;
    _cooldownUntil = null;
    _rateLimitError = null;
  }

  Future<dynamic> get(Uri uri, Future<dynamic> Function() fetch) async {
    final policy = DanmakuCachePolicy.forUri(uri);
    if (policy == null || !_enabled() || _privateMode()) return fetch();
    final key = DanmakuCachePolicy.keyFor(uri);
    final previous = _pending[key];
    if (previous != null) return previous;
    final future = _load(key, policy, fetch, _epoch);
    _pending[key] = future;
    try {
      return await future;
    } finally {
      if (identical(_pending[key], future)) _pending.remove(key);
    }
  }

  Future<dynamic> _load(String key, DanmakuCachePolicy policy,
      Future<dynamic> Function() fetch, int epoch) async {
    Map? saved;
    try {
      saved = await _call(
          'read', {'key': key, 'ttl': policy.freshFor.inMilliseconds}) as Map?;
      if (saved != null && !policy.accepts(saved['value'])) saved = null;
    } catch (_) {/* Cache I/O must not prevent online playback. */}
    if (saved?['fresh'] == true) return saved!['value'];
    // An expired empty result cannot help playback or hide a new 429.
    if (saved != null && policy.isEmpty(saved['value'])) saved = null;
    if (_cooldownUntil != null && _clock().isBefore(_cooldownUntil!)) {
      if (saved != null) return saved['value'];
      throw _rateLimitError!;
    }
    try {
      final value = await fetch();
      if (!policy.accepts(value)) return value;
      final empty = policy.isEmpty(value);
      if (empty && saved != null && !policy.isEmpty(saved['value'])) {
        return saved['value'];
      }
      if (epoch == _epoch && _enabled() && !_privateMode()) {
        try {
          await _call('write', {'key': key, 'value': value, 'empty': empty});
        } catch (_) {/* A full disk does not discard a successful response. */}
      }
      return value;
    } catch (error) {
      if (error is NetworkException) {
        if (error.type == NetworkExceptionType.cancel ||
            error.statusCode == 401 ||
            error.statusCode == 403) {
          rethrow;
        }
        if (error.statusCode == 429) {
          _rateLimitError = error;
          var wait = const Duration(minutes: 15);
          final raw = error.rawError;
          if (raw is DioException) {
            final header = raw.response?.headers.value('retry-after');
            final seconds = int.tryParse(header ?? '');
            DateTime? deadline;
            try {
              deadline = HttpDate.parse(header ?? '');
            } catch (_) {}
            final requested = seconds != null
                ? Duration(seconds: seconds)
                : deadline?.difference(_clock());
            if (requested != null && requested > wait) wait = requested;
          }
          _cooldownUntil = _clock().add(wait);
        }
      }
      if (saved != null) return saved['value'];
      rethrow;
    }
  }
}

void _runCache(List<dynamic> args) async {
  final inbox = ReceivePort();
  var now = DateTime.now();
  final store =
      DanmakuCacheStore(Directory(args[1] as String), clock: () => now);
  (args[0] as SendPort).send(inbox.sendPort);
  await for (final message in inbox) {
    final request = message as List;
    final reply = request[0] as SendPort;
    final args = request[2] as Map;
    try {
      now = DateTime.fromMillisecondsSinceEpoch(args['now'] as int);
      store.limitBytes = args['limit'] as int;
      dynamic value;
      switch (request[1]) {
        case 'read':
          value = await store.read(args['key'] as String,
              Duration(milliseconds: args['ttl'] as int));
        case 'write':
          await store.write(args['key'] as String, args['value'],
              empty: args['empty'] as bool);
        case 'stats':
          value = await store.stats();
        case 'clear':
          await store.clear();
        case 'trim':
          await store.initialize();
          await store.trim();
      }
      reply.send({'value': value});
    } catch (error) {
      reply.send({'error': error.toString()});
    }
  }
}
