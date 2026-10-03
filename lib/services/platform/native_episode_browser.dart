import 'package:flutter/services.dart';
import 'package:kazumi/utils/async_session.dart';

/// A UI-only snapshot. Source URLs, credentials and playback state stay in Dart.
class EpisodeBrowserItem {
  const EpisodeBrowserItem({
    required this.opaqueId,
    required this.label,
    this.current = false,
    this.seen = false,
  });

  final String opaqueId;
  final String label;
  final bool current;
  final bool seen;

  Map<String, Object> toMap() => {
        'opaqueId': opaqueId,
        'label': label,
        'current': current,
        'seen': seen,
      };
}

class EpisodeBrowserSnapshot {
  EpisodeBrowserSnapshot({
    required this.sessionId,
    required this.revision,
    required List<EpisodeBrowserItem> items,
    this.initialOpaqueId,
  }) : items = List.unmodifiable(items) {
    final ids = items.map((item) => item.opaqueId).toSet();
    if (sessionId.isEmpty ||
        sessionId.length > 128 ||
        revision < 0 ||
        items.isEmpty ||
        items.length > 5000 ||
        ids.length != items.length ||
        items.any((item) =>
            item.opaqueId.isEmpty ||
            item.opaqueId.length > 128 ||
            item.label.length > 256) ||
        (initialOpaqueId != null && !ids.contains(initialOpaqueId))) {
      throw ArgumentError('Invalid episode UI snapshot');
    }
  }

  final String sessionId;
  final int revision;
  final List<EpisodeBrowserItem> items;
  final String? initialOpaqueId;

  Map<String, Object?> toMap() => {
        'sessionId': sessionId,
        'revision': revision,
        'items': items.map((item) => item.toMap()).toList(growable: false),
        'initialOpaqueId': initialOpaqueId,
      };
}

/// Validates the native command before any caller invokes a Dart action.
class EpisodeBrowserCommandGate {
  EpisodeBrowserCommandGate(this.snapshot);

  final EpisodeBrowserSnapshot snapshot;
  bool _closed = false;

  String? consume(Object? result, {required bool current}) {
    if (_closed || !current || result is! Map) return null;
    const fields = {'sessionId', 'revision', 'commandId', 'action', 'opaqueId'};
    if (result.keys.any((key) => !fields.contains(key)) ||
        result['sessionId'] != snapshot.sessionId ||
        result['revision'] is! int ||
        result['revision'] != snapshot.revision ||
        result['commandId'] is! String ||
        (result['commandId'] as String).isEmpty ||
        (result['commandId'] as String).length > 128) {
      return null;
    }
    if (result['action'] == 'cancelled' && result['opaqueId'] == null) {
      _closed = true;
      return null;
    }
    final id = result['opaqueId'];
    if (result['action'] != 'selected' ||
        id is! String ||
        !snapshot.items.any((item) => item.opaqueId == id)) {
      return null;
    }
    _closed = true;
    return id;
  }
}

class EpisodeBrowserUnavailable implements Exception {
  const EpisodeBrowserUnavailable();
}

class NativeEpisodeBrowser {
  NativeEpisodeBrowser({
    MethodChannel channel =
        const MethodChannel('com.predidit.kazumi/episode_browser'),
  }) : _channel = channel;

  final MethodChannel _channel;
  final _sessions = AsyncSessionOwner();
  EpisodeBrowserSnapshot? _pending;

  Future<String?> show(EpisodeBrowserSnapshot snapshot,
      {required bool Function() isCurrent}) async {
    if (_sessions.isClosed || _pending != null) return null;
    final session = _sessions.begin();
    _pending = snapshot;
    try {
      final result =
          await _channel.invokeMethod<Object?>('show', snapshot.toMap());
      return EpisodeBrowserCommandGate(snapshot)
          .consume(result, current: session.isActive && isCurrent());
    } on MissingPluginException {
      if (session.isActive && isCurrent()) {
        throw const EpisodeBrowserUnavailable();
      }
      return null;
    } on PlatformException {
      if (session.isActive && isCurrent()) {
        throw const EpisodeBrowserUnavailable();
      }
      return null;
    } finally {
      if (identical(_pending, snapshot)) _pending = null;
    }
  }

  Future<void> cancel() async {
    _sessions.cancel();
    final pending = _pending;
    if (pending == null) return;
    try {
      await _channel.invokeMethod<void>('cancel', {
        'sessionId': pending.sessionId,
        'revision': pending.revision,
      });
    } on PlatformException {
      // The UI request is already cancelled locally; Android may be detached.
    } on MissingPluginException {
      // Flutter fallback remains available on builds without the component.
    }
  }

  Future<void> dispose() async {
    _sessions.close();
    await cancel();
  }
}
