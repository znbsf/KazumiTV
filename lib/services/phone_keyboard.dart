import 'dart:async';
import 'dart:io';
import 'package:flutter/widgets.dart';
import 'package:kazumi/services/phone_keyboard_session.dart';
import 'package:kazumi/services/platform/app_remote.dart';

/// App-owned temporary session; opening/closing a control dialog does not own it.
class PhoneKeyboard extends ChangeNotifier with WidgetsBindingObserver {
  PhoneKeyboard() {
    WidgetsBinding.instance.addObserver(this);
  }
  static final instance = PhoneKeyboard();
  PhoneKeyboardSession? session;
  PhoneKeyboardTarget? _target;
  String? error;
  bool starting = false;
  int _controlDialogs = 0;
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

  Future<void> start({InternetAddress? address}) async {
    if (starting || uri != null) return;
    starting = true;
    error = null;
    notifyListeners();
    final next = PhoneKeyboardSession(
        remoteState: () => _controlDialogs > 0
            ? {'context': '电视连接设置（仅本地操作）', 'revision': -1, 'keys': <Object>[]}
            : AppRemote.instance.state,
        dispatchRemote: (id, {required revision}) => _controlDialogs > 0
            ? Future.value(false)
            : AppRemote.instance.dispatch(id, revision: revision),
        onConnected: notifyListeners,
        onClosed: () {
          error = '连接已断开或闲置过期，请重新开启';
          notifyListeners();
        });
    session = next;
    next.setTarget(_target);
    try {
      await next.start(address: address);
    } catch (_) {
      await next.close();
      error = '无法开启手机键盘，请检查电视的局域网连接';
    } finally {
      starting = false;
      notifyListeners();
    }
  }

  Future<void> disconnect() async {
    await session?.close();
    notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(disconnect());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(session?.close());
    super.dispose();
  }
}
