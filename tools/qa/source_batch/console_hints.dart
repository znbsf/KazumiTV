// QA-only in-memory hints from one owned controller's untrusted log stream.
// No controller mutation, JavaScript, transport, logging or raw-text retention.
import 'dart:async';
import 'dart:convert';

const qaConsoleCaseId = 'qa-mgnacg-console-hints-v1';
const qaConsoleRuleSha =
    '7f3be15356c80e105ad8f42e496833eb10906ffd3647e609dd544057d3f62e12';
const qaConsolePageSha =
    '29e2d9f0f2d27ece7253adcce47d3989a6cbefe79fab32a0d5e22b53925e9cd8';

bool qaConsoleRequested(Map<String, dynamic> config) {
  if (!config.containsKey('console_hint_observer')) return false;
  final value = config['console_hint_observer'];
  if (value is! bool) {
    throw const FormatException('QA console opt-in must be boolean');
  }
  return value;
}

bool qaMgnacgConsoleBinding(Map<String, dynamic> config,
    Map<String, Object?> rule, Map<String, dynamic> environment) {
  const allowed = {
    'id',
    'group',
    'engine',
    'source_key',
    'work_key',
    'keyword',
    'names',
    'rule',
    'rule_variant',
    'rule_provenance',
    'candidate_ordinal',
    'identity_basis',
    'canonical_subject_id',
    'road',
    'episode',
    'expected_episode_page_sha256',
    'expected_episode_label',
    'user_agent',
    'repeat',
    'console_hint_observer',
    'app_gecko_fallback',
    'observe_media_root'
  };
  final names = config['names'];
  return config['console_hint_observer'] == true &&
      config.keys.every(allowed.contains) &&
      config['id'] == qaConsoleCaseId &&
      config['group'] == 'console-hints' &&
      config['source_key'] == 'mgnacg' &&
      config['keyword'] == '学生会也有洞' &&
      config['rule'] is Map &&
      config['rule_variant'] == 'effective' &&
      config['repeat'] == 0 &&
      names is List &&
      names.length == 1 &&
      names.single == '学生会也有洞！' &&
      config['road'] == 0 &&
      config['episode'] == 1 &&
      config['expected_episode_page_sha256'] == qaConsolePageSha &&
      config['expected_episode_label'] == '第2话' &&
      config['engine'] == 'app' &&
      (!config.containsKey('app_gecko_fallback') ||
          config['app_gecko_fallback'] == false) &&
      (!config.containsKey('observe_media_root') ||
          config['observe_media_root'] == false) &&
      rule['name'] == 'mgnacg' &&
      rule['version'] == '1.2' &&
      rule['api'] == '9' &&
      rule['effective_sha256'] == qaConsoleRuleSha &&
      rule['variant'] == 'effective' &&
      rule['overlay'] == false &&
      environment['sdk'] == 28 &&
      environment['webview'] == 'com.android.webview/66.0.3359.158' &&
      environment['package'] == 'com.znbsf.kazumi.fluttertv.parserqa';
}

enum QaConsoleHint {
  syntax,
  reference,
  type,
  cors,
  csp,
  mixedContent,
  blockedResource,
  unclassified,
  challenge
}

enum QaConsoleStop {
  completed,
  cancelled,
  quota,
  challengeHint,
  streamError,
  attributionLost
}

class QaConsoleHintCounter {
  static const maxRecords = 80, maxCodeUnits = 8192, maxUtf8Bytes = 256 * 1024;
  // This exact spelling is emitted by the pinned plugin's ConsoleMessageLevel.
  static final _prefix =
      RegExp(r'^Console \[(?:TIP|LOG|WARNING|ERROR|DEBUG)\]: ');
  final _counts = {for (final hint in QaConsoleHint.values) hint: 0};
  int _records = 0, _bytes = 0;
  bool _sealed = false, _overflow = false, _challenge = false;

  QaConsoleStop? accept(String raw) {
    if (_sealed) return null;
    final prefix = _prefix.firstMatch(raw);
    if (prefix == null) return null;
    if (_records >= maxRecords || raw.length > maxCodeUnits) {
      _overflow = _sealed = true;
      return QaConsoleStop.quota;
    }
    final size = utf8.encode(raw).length;
    if (_bytes + size > maxUtf8Bytes) {
      _overflow = _sealed = true;
      return QaConsoleStop.quota;
    }
    _records++;
    _bytes += size;
    var end = raw.length;
    for (final separator in ['\r', '\n']) {
      final index = raw.indexOf(separator, prefix.end);
      if (index >= 0 && index < end) end = index;
    }
    final line = raw.substring(prefix.end, end).trimLeft().toLowerCase();
    final hint = _classify(line);
    _counts[hint] = _counts[hint]! + 1;
    if (hint == QaConsoleHint.challenge) {
      _challenge = _sealed = true;
      return QaConsoleStop.challengeHint;
    }
    return null;
  }

  static QaConsoleHint _classify(String text) {
    // Header-like lines and subsequent stack lines never become error evidence.
    if (text.startsWith('cookie:') ||
        text.startsWith('set-cookie:') ||
        text.startsWith('authorization:') ||
        text.startsWith('proxy-authorization:')) {
      return QaConsoleHint.unclassified;
    }
    if (text.contains('captcha') ||
        text.contains('challenge-platform') ||
        text.contains('cf-chl-') ||
        text.contains('turnstile') ||
        text.contains('verify you are human') ||
        text.startsWith('just a moment')) {
      return QaConsoleHint.challenge;
    }
    if (text.contains('cors policy') ||
        text.contains('cross-origin request blocked')) {
      return QaConsoleHint.cors;
    }
    if (text.contains('content security policy') ||
        text.contains('content-security-policy')) {
      return QaConsoleHint.csp;
    }
    if (text.startsWith('mixed content:')) return QaConsoleHint.mixedContent;
    if (text.contains('net::err_blocked_by_client') ||
        text.contains('net::err_blocked_by_response')) {
      return QaConsoleHint.blockedResource;
    }
    final error = RegExp(
            r'^(?:uncaught(?: \(in promise\))? )?(syntaxerror|referenceerror|typeerror)\s*:')
        .firstMatch(text);
    return switch (error?.group(1)) {
      'syntaxerror' => QaConsoleHint.syntax,
      'referenceerror' => QaConsoleHint.reference,
      'typeerror' => QaConsoleHint.type,
      _ => QaConsoleHint.unclassified,
    };
  }

  void seal() {
    _sealed = true;
  }

  Map<String, Object?> snapshot() => {
        'counts': {
          for (final hint in QaConsoleHint.values) hint.name: _counts[hint]
        },
        'accepted_records': _records,
        'accepted_utf8_bytes': _bytes,
        'overflow': _overflow,
        'challengeHint': _challenge,
        'hints_only': true,
        'console_authenticity_verified': false,
        'frame_origin_available': false,
      };
}

class QaConsoleHintObserver {
  QaConsoleHintObserver(
      {required this.isCurrent,
      required this.onChallengeHint,
      required this.onUnavailable});
  final bool Function() isCurrent;
  final void Function() onChallengeHint, onUnavailable;
  final _counter = QaConsoleHintCounter();
  StreamSubscription<String>? _subscription;
  final _attached = Completer<void>();
  bool _started = false,
      _subscribed = false,
      _closed = false,
      _streamError = false,
      _callbackError = false;
  QaConsoleStop? _reason;
  Future<bool>? _closing;
  bool? _cleanup;

  bool _current() {
    if (_closed) return false;
    try {
      if (isCurrent()) return true;
    } catch (_) {/* Never stringify caller exceptions. */}
    stop(QaConsoleStop.attributionLost);
    _notify(onUnavailable);
    return false;
  }

  bool attach(Stream<String> Function() logs) {
    if (_started || !_current()) return false;
    _started = true;
    try {
      _subscription = logs().listen(_event,
          onError: (Object ignored, StackTrace ignoredStack) {
        if (_closed) return;
        _streamError = true;
        stop(QaConsoleStop.streamError);
        _notify(onUnavailable);
      }, onDone: () {
        stop();
      });
      _subscribed = true;
    } catch (_) {
      _streamError = true;
      stop(QaConsoleStop.streamError);
      _notify(onUnavailable);
    } finally {
      _attached.complete();
    }
    return !_streamError;
  }

  void _event(String raw) {
    if (!_current()) return;
    final reason = _counter.accept(raw);
    if (reason == null) return;
    stop(reason);
    if (reason == QaConsoleStop.challengeHint) _notify(onChallengeHint);
  }

  void _notify(void Function() callback) {
    try {
      callback();
    } catch (_) {
      _callbackError = true;
    }
  }

  Future<bool> stop([QaConsoleStop reason = QaConsoleStop.completed]) {
    _closed = true;
    _counter.seal();
    _reason ??= reason;
    return _closing ??= _cancel();
  }

  Future<bool> _cancel() async {
    if (_started) {
      await _attached.future; // Also handles emission during listen().
    }
    try {
      await _subscription?.cancel();
      return _cleanup = true;
    } catch (_) {
      return _cleanup = false;
    } finally {
      _subscription = null;
    }
  }

  Map<String, Object?> snapshot() => {
        ..._counter.snapshot(),
        'stop_reason': _reason?.name,
        'subscribed': _subscribed,
        'streamError': _streamError,
        'callback_error': _callbackError,
        'subscription_cleanup': !_subscribed
            ? 'not_created'
            : _cleanup == null
                ? 'pending'
                : _cleanup!
                    ? 'confirmed'
                    : 'unconfirmed',
      };
}

QaConsoleHintObserver? createBoundQaConsoleObserver({
  required Map<String, dynamic> config,
  required Map<String, Object?> rule,
  required Map<String, dynamic> environment,
  required Stream<String> Function() logs,
  required bool Function() isCurrent,
  required void Function() onChallengeHint,
  required void Function() onUnavailable,
}) {
  if (!qaMgnacgConsoleBinding(config, rule, environment)) return null;
  final observer = QaConsoleHintObserver(
      isCurrent: isCurrent,
      onChallengeHint: onChallengeHint,
      onUnavailable: onUnavailable);
  observer.attach(logs);
  return observer;
}
