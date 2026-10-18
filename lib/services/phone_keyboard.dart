import 'dart:async';
import 'dart:io';
import 'package:flutter/widgets.dart';
import 'package:kazumi/services/phone_keyboard_session.dart';
import 'package:kazumi/services/platform/app_remote.dart';
import 'package:kazumi/services/storage/phone_remote_pairing.dart';

/// App-owned listener; optional pairing survives restarts, text consent does not.
class PhoneKeyboard extends ChangeNotifier with WidgetsBindingObserver {
  PhoneKeyboard({PhoneRemotePairingStore? pairingStore})
      : _pairingStore = pairingStore ?? PhoneRemotePairingStore() {
    WidgetsBinding.instance.addObserver(this);
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
  }
  static final instance = PhoneKeyboard();
  PhoneKeyboardSession? session;
  PhoneKeyboardTarget? _target;
  String? error;
  bool starting = false;
  int _controlDialogs = 0;
  final PhoneRemotePairingStore _pairingStore;
  PhoneRemotePairing? _pairing;
  Future<void> _operations = Future<void>.value();
  Future<void> _closing = Future<void>.value();
  bool _foreground = true;
  bool _disposed = false;
  bool _loaded = false;
  int _epoch = 0;
  InternetAddress? _address;
  DateTime? get pairingExpiresAt => _pairing?.expiresAt;
  bool get hasPairing => _pairing != null;
  bool get isPaused => _pairing?.paused ?? false;
  int get onlineCount => session?.onlineCount ?? 0;
  Future<void> _enqueue(Future<void> Function() operation) {
    return _operations = _operations.then((_) async {
      if (_disposed) return;
      try {
        await operation();
      } catch (_) {
        error = '连接设置未能保存或恢复，请重试';
      }
      if (!_disposed) notifyListeners();
    });
  }

  void enterControlDialog() {
    _controlDialogs++;
    session?.invalidateRemoteRequests();
  }

  void leaveControlDialog() {
    if (_controlDialogs > 0) _controlDialogs--;
    session?.invalidateRemoteRequests();
  }

  Uri? get uri => session?.isClosed == false ? session?.uri : null;
  bool get readTextAllowed => session?.readTextAllowed ?? false;
  void setReadTextAllowed(bool value) {
    session?.setReadTextAllowed(value);
    notifyListeners();
  }

  void attach(PhoneKeyboardTarget target) {
    _target = target;
    session?.setTarget(target);
  }

  void detach(PhoneKeyboardTarget target) {
    if (identical(target, _target)) {
      _target = null;
      session?.setTarget(null);
    }
  }

  Future<void> start({InternetAddress? address, bool remember = false}) {
    final epoch = _epoch;
    return _enqueue(
        () => _start(address: address, remember: remember, epoch: epoch));
  }

  Future<void> restore({InternetAddress? address, bool resume = false}) {
    final epoch = _epoch;
    return _enqueue(() async {
      if (!_foreground || epoch != _epoch) return;
      if (!_loaded) {
        _pairing = await _pairingStore.read();
        _loaded = true;
      }
      if (_pairing == null) return;
      if (!_pairing!.validAt(DateTime.now())) {
        _pairing = null;
        error = '7 天配对已到期，请重新扫码';
        return;
      }
      if (_pairing!.paused) {
        if (!resume) return;
        final resumed = _pairing!.withPaused(false);
        await _pairingStore.write(resumed);
        _pairing = resumed;
      }
      await _start(address: address ?? _address, remember: true, epoch: epoch);
    });
  }

  Future<void> _start(
      {InternetAddress? address,
      required bool remember,
      required int epoch}) async {
    await _closing;
    if (!_foreground || epoch != _epoch || _disposed || uri != null) return;
    _address = address;
    starting = true;
    error = null;
    notifyListeners();
    final created = DateTime.now();
    final saved = _pairing;
    final expires = remember
        ? saved?.expiresAt ?? created.add(const Duration(days: 7))
        : null;
    final next = PhoneKeyboardSession(
        accessToken: saved?.token,
        port: saved?.port ?? 0,
        expiresAt: expires,
        remoteState: () => _controlDialogs > 0
            ? {'context': '电视连接设置（仅本地操作）', 'revision': -1, 'keys': <Object>[]}
            : AppRemote.instance.state,
        dispatchRemote: (id, {required revision}) => _controlDialogs > 0
            ? Future.value(false)
            : AppRemote.instance.dispatch(id, revision: revision),
        onPresenceChanged: () {
          if (!_disposed) notifyListeners();
        },
        onClosed: () {
          if (!_disposed) {
            if (expires != null && !DateTime.now().isBefore(expires)) {
              _pairing = null;
            }
            error = expires != null && !DateTime.now().isBefore(expires)
                ? '7 天配对已到期，请重新扫码'
                : hasPairing
                    ? '连接已暂停，回到应用后恢复'
                    : '连接已断开或闲置过期，请重新开启';
            notifyListeners();
          }
        });
    session = next;
    next.setTarget(_target);
    try {
      await next.start(address: address);
      if (remember) {
        final pairing = saved ??
            PhoneRemotePairing(
                token: next.token,
                port: next.uri!.port,
                createdAt: created,
                expiresAt: expires!);
        if (saved == null) await _pairingStore.write(pairing);
        _pairing = pairing;
        _loaded = true;
      }
      if (_disposed || !_foreground || epoch != _epoch) await next.close();
    } catch (_) {
      await next.close();
      error = '无法开启手机遥控，请检查局域网或重试；已有配对不会自动更换端口';
    } finally {
      starting = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> disconnect() {
    _epoch++;
    _closing = session?.close() ?? Future<void>.value();
    return _enqueue(() async {
      await _closing;
      if (_pairing != null) await _pairingStore.clear();
      _pairing = null;
      _loaded = true;
      error = null;
    });
  }

  /// Stop all clients without revoking the seven-day capability. A deliberate
  /// pause survives app restarts, so browser polling cannot undo the TV action.
  Future<void> pause() {
    _epoch++;
    _closing = session?.close() ?? Future<void>.value();
    return _enqueue(() async {
      await _closing;
      if (_pairing != null) {
        final paused = _pairing!.withPaused(true);
        _pairing = paused;
        await _pairingStore.write(paused);
      }
      error = null;
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _foreground = false;
      _epoch++;
      _closing = session?.close() ?? Future<void>.value();
    } else if (state == AppLifecycleState.resumed) {
      _foreground = true;
      unawaited(restore());
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _epoch++;
    WidgetsBinding.instance.removeObserver(this);
    unawaited(session?.close());
    super.dispose();
  }
}
