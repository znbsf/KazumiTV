import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:kazumi/bean/widget/tv_desktop_navigation.dart';

typedef TvProbeStateReader = Map<String, Object?> Function();

/// Optional, bounded memory-only observations. This never handles a key,
/// schedules a frame, queries a player or performs I/O while collecting.
class TvInputLifecycle {
  TvInputLifecycle(this.nowMicros);

  final int Function() nowMicros;
  static TvInputLifecycle? _installed;
  static bool get enabled => _installed != null;
  static bool get active => _installed?._open ?? false;
  final Map<
      Object,
      ({
        bool Function() current,
        TvProbeStateReader read,
        List<int> Function() catalog
      })> _providers = {};
  final _sequences = Expando<int>('tv-input-sequence');
  final Map<String, List<Map<String, Object?>>> _events = {};
  final Set<int> _pressed = {};
  bool _open = false;
  int _start = 0;
  int _end = 0;
  int _sequence = 0;
  int _dropped = 0;
  int _readErrors = 0;
  List<int> _pressedStart = [];
  List<int> _pressedEnd = [];
  Map<String, Object?>? _catalogStart;
  Map<String, Object?>? _catalogEnd;
  bool _scrollComplete = false;

  void install() {
    assert(_installed == null);
    _installed = this;
    HardwareKeyboard.instance.addHandler(_hardwareKey);
    FocusManager.instance.addListener(_focus);
  }

  void dispose() {
    HardwareKeyboard.instance.removeHandler(_hardwareKey);
    FocusManager.instance.removeListener(_focus);
    if (identical(_installed, this)) _installed = null;
    _open = false;
    _providers.clear();
  }

  static VoidCallback registerPageState(
    Object owner, {
    required bool Function() isCurrent,
    required TvProbeStateReader read,
    required List<int> Function() readCatalogIds,
  }) {
    final instance = _installed;
    if (instance == null || instance._providers.length >= 8) return () {};
    final lease = (current: isCurrent, read: read, catalog: readCatalogIds);
    instance._providers[owner] = lease;
    return () {
      if (instance._providers[owner] == lease) {
        instance._providers.remove(owner);
      }
    };
  }

  Map<String, Object?> _state() {
    for (final provider in _providers.values.toList().reversed) {
      try {
        if (provider.current()) {
          final state = provider.read();
          if (_open && state['scrollTraceEnabled'] != true)
            _scrollComplete = false;
          return state;
        }
      } catch (_) {
        _readErrors++;
      }
    }
    if (_open) _scrollComplete = false;
    return {'route': null};
  }

  Map<String, Object?> _identity() {
    final node = FocusManager.instance.primaryFocus;
    final home = node == null ? null : TvDesktopNavigation.homeFocusOf(node);
    final state = _state();
    return {
      'route': state['route'],
      'itemId': home?.subjectId,
      'controlId': home?.kind == TvHomeFocusKind.category
          ? 'category:${home?.category}'
          : null,
      'focusKind': home?.kind.name,
      'channelNumber': home?.channelNumber,
      'processLocalFocusIdentity': node == null ? null : identityHashCode(node),
    };
  }

  void start(int startedAtUs) {
    _start = startedAtUs;
    _end = _start;
    _sequence = _dropped = _readErrors = 0;
    _events.clear();
    _catalogStart = null;
    _catalogEnd = null;
    _pressedStart = _pressed.toList();
    _pressedEnd = [];
    _open = true;
    final state = _state();
    _scrollComplete = state['scrollTraceEnabled'] == true;
    for (final provider in _providers.values.toList().reversed) {
      try {
        if (!provider.current()) continue;
        final ids = provider.catalog();
        if (ids.length > 512) _dropped++;
        _catalogStart = {...state, 'ids': ids.take(512).toList()};
        break;
      } catch (_) {
        _readErrors++;
      }
    }
    _append('focusEvents', {..._identity(), 'initial': true});
    if (state['scrollOffset'] is num) {
      _append('scrollEvents', {
        'route': state['route'],
        'offset': state['scrollOffset'],
        'initial': true
      });
    }
    _append('checkpoints', {
      'name': 'start',
      'state': {...state, ..._identity()}
    });
  }

  void stop() {
    if (!_open) return;
    _append('checkpoints', {
      'name': 'end',
      'state': {..._state(), ..._identity()}
    });
    for (final provider in _providers.values.toList().reversed) {
      try {
        if (!provider.current()) continue;
        final ids = provider.catalog();
        if (ids.length > 512) _dropped++;
        _catalogEnd = {...provider.read(), 'ids': ids.take(512).toList()};
        break;
      } catch (_) {
        _readErrors++;
      }
    }
    _end = nowMicros();
    _pressedEnd = _pressed.toList();
    _open = false;
  }

  void _append(String stream, Map<String, Object?> fields) {
    if (!_open) return;
    final list = _events.putIfAbsent(stream, () => []);
    final limit = stream == 'scrollEvents' ? 2048 : 512;
    if (list.length >= limit) {
      _dropped++;
      return;
    }
    list.add({'atUs': nowMicros() - _start, ...fields});
  }

  static void trace(String kind, Map<String, Object?> fields,
      {KeyEvent? inputEvent}) {
    final instance = _installed;
    if (instance == null || !instance._open) return;
    instance._append('gridEvents', {
      'kind': kind,
      'inputSeq': inputEvent == null ? null : instance._sequences[inputEvent],
      ...fields
    });
  }

  static void scrollChanged(String route, double offset) {
    _installed?._append('scrollEvents', {'route': route, 'offset': offset});
  }

  static void checkpoint(String name) {
    final instance = _installed;
    if (instance == null || !instance._open) return;
    final identity = instance._identity();
    instance._append('focusEvents', identity);
    instance._append('checkpoints', {
      'name': name,
      'state': {...instance._state(), ...identity}
    });
  }

  static void platformAction(String action, String stage, {bool? didPop}) {
    _installed?._append('platformActions', {
      'action': action,
      'stage': stage,
      'didPop': didPop,
      'clock': 'dart_monotonic_us',
    });
  }

  void _focus() {
    if (_open) _append('focusEvents', _identity());
  }

  // The pinned Flutter KeyEventManager calls HardwareKeyboard handlers before
  // dispatching its KeyMessage to FocusManager (including early handlers).
  // This also observes keys when there is no primary focus. The order is
  // exercised against a real widget handler in tv_input_lifecycle_test.dart.
  bool _hardwareKey(KeyEvent event) {
    _observeKey(event, 'HardwareKeyboard.before_focus_routing');
    return false;
  }

  KeyEventResult _observeKey(KeyEvent event, String source) {
    final logical = event.logicalKey;
    if (logical == LogicalKeyboardKey.f9 || logical == LogicalKeyboardKey.f10) {
      return KeyEventResult.ignored;
    }
    if (_sequences[event] != null) return KeyEventResult.ignored;
    _sequences[event] = _open ? ++_sequence : 0;
    if (event is KeyUpEvent) {
      _pressed.remove(event.physicalKey.usbHidUsage);
    } else {
      _pressed.add(event.physicalKey.usbHidUsage);
    }
    if (!_open) return KeyEventResult.ignored;
    final seq = _sequences[event]!;
    final key = switch (logical) {
      LogicalKeyboardKey.arrowDown => 'down',
      LogicalKeyboardKey.arrowUp => 'up',
      LogicalKeyboardKey.arrowLeft => 'left',
      LogicalKeyboardKey.arrowRight => 'right',
      LogicalKeyboardKey.select ||
      LogicalKeyboardKey.enter ||
      LogicalKeyboardKey.numpadEnter ||
      LogicalKeyboardKey.space =>
        'select',
      LogicalKeyboardKey.escape || LogicalKeyboardKey.goBack => 'back',
      _ => 'keyId:${logical.keyId}',
    };
    _append('appEvents', {
      'seq': seq,
      'key': key,
      'type': event is KeyUpEvent
          ? 'up'
          : (event is KeyRepeatEvent ? 'repeat' : 'down'),
      'synthesized': event.synthesized,
      'logicalKeyId': logical.keyId,
      'physicalKeyId': event.physicalKey.usbHidUsage,
      'inputSource': source,
      ..._identity()
    });
    _append('checkpoints', {
      'name': 'input:$seq',
      'state': {..._state(), ..._identity()}
    });
    return KeyEventResult.ignored;
  }

  Map<String, Object?> report() {
    assert(!_open);
    return {
      'schema': 1,
      'clock': 'dart_monotonic_us',
      'appEventSource': 'HardwareKeyboard.before_focus_routing',
      'durationUs': _end - _start,
      'logging': {
        'appComplete':
            _dropped == 0 && _pressedStart.isEmpty && _pressedEnd.isEmpty,
        'includesKeyUp': true,
        'focusComplete': _dropped == 0 && _readErrors == 0,
        'scrollComplete': _scrollComplete && _dropped == 0 && _readErrors == 0,
        'dropped': _dropped,
        'stateReadErrors': _readErrors,
        'routeCoverage': 'registered_current_page_only',
      },
      'pressedAtStart': _pressedStart,
      'pressedAtEnd': _pressedEnd,
      'catalogStart': _catalogStart,
      'catalogEnd': _catalogEnd,
      for (final key in [
        'appEvents',
        'focusEvents',
        'scrollEvents',
        'checkpoints',
        'gridEvents',
        'platformActions'
      ])
        key: _events[key] ?? [],
    };
  }
}
