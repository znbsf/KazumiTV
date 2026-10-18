import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:kazumi/services/logging/logger.dart';

typedef PlaybackTraceSink = void Function(String record);

/// A small, request-owned flight recorder. No native queries or network work.
/// Sanitization happens before buffering; failures survive normal-mode retries.
class PlaybackTrace {
  PlaybackTrace(this.scope, {PlaybackTraceSink? sink})
      : _sink = sink ?? _persist,
        id = '${DateTime.now().microsecondsSinceEpoch}-${_sequence++}';

  static int _sequence = 0;
  static const maxEvents = 12;
  static const maxDetail = 600;
  final String scope;
  final String id;
  final PlaybackTraceSink _sink;
  final Stopwatch _clock = Stopwatch()..start();
  final List<Map<String, Object?>> _events = [];
  bool _finished = false;

  static void _persist(String record) =>
      KazumiLogger().i('PlaybackTrace $record', forceLog: true);

  /// Keep a host and opaque correlation key, never a path, query or userinfo.
  static String resource(String value) {
    final uri = Uri.tryParse(value);
    final host = uri != null && ['http', 'https'].contains(uri.scheme)
        ? uri.host
        : 'local-or-invalid';
    final key = sha256.convert(utf8.encode(value)).toString().substring(0, 12);
    return '$host#$key';
  }

  static String safeDetail(Object? value) {
    var text = '$value';
    // Decode only for redaction; never change the actual playback URL.
    for (var i = 0; i < 2; i++) {
      try {
        final decoded = Uri.decodeFull(text);
        if (decoded == text) break;
        text = decoded;
      } on FormatException {
        break;
      }
    }
    text = text.replaceAll(RegExp(r'\x1b\[[0-9;]*m'), '');
    text = text.replaceAll(
        RegExp(r'''(?:https?|file|content)://[^\s<>"']+''',
            caseSensitive: false),
        '[resource]');
    text = text.replaceAll(
        RegExp(
            r'(?:authorization|proxy-authorization|cookie|set-cookie)\s*[:=][^\r\n]*',
            caseSensitive: false),
        '[credentials omitted]');
    text = text.replaceAll(
        RegExp(
            r'''\b(?:token|access_token|refresh_token|sign|signature|password|secret|api[_-]?key)\s*[:=]\s*[^\s,;]+''',
            caseSensitive: false),
        '[secret omitted]');
    text = text.replaceAll(RegExp(r'\bBearer\s+\S+', caseSensitive: false),
        '[credentials omitted]');
    text = text.replaceAll(RegExp(r'\b[A-Za-z0-9_+/=-]{48,}\b'), '[opaque]');
    text = text.replaceAll(RegExp(r'[\x00-\x1f\x7f\s]+'), ' ').trim();
    return text.length <= maxDetail ? text : '${text.substring(0, maxDetail)}…';
  }

  void event(String stage, {Object? detail, String? url}) {
    if (_finished) return;
    if (_events.length == maxEvents) _events.removeAt(1);
    _events.add({
      'ms': _clock.elapsedMilliseconds,
      'stage': stage,
      if (detail != null) 'detail': safeDetail(detail),
      if (url != null) 'resource': resource(url),
    });
  }

  void finish(String outcome, {Object? error}) {
    if (_finished) return;
    _finished = true;
    // Diagnostics must never change the playback outcome, even if a sink fails.
    try {
      _sink(jsonEncode({
        'schema': 1,
        'timeUtc': DateTime.now().toUtc().toIso8601String(),
        'session': id,
        'scope': scope,
        'outcome': outcome,
        'elapsedMs': _clock.elapsedMilliseconds,
        if (error != null) 'error': safeDetail(error),
        'events': _events,
      }));
    } catch (_) {}
  }
}
