import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

String _randomId() => List.generate(16, (_) => Random.secure().nextInt(256))
    .map((v) => v.toRadixString(16).padLeft(2, '0'))
    .join();

/// Only an explicitly opened editor may own a target.
/// Credentials use writeOnly; ordinary text needs session-scoped read consent.
class PhoneKeyboardTarget {
  PhoneKeyboardTarget(
      {required this.label,
      required this.onText,
      required this.onConfirm,
      this.readValue,
      this.onSelection,
      this.isActive,
      this.writeOnly = false,
      this.maxLength = 2048});
  final String id = _randomId();
  final String label;
  final int maxLength;
  final bool writeOnly;
  final void Function(String) onText;
  final void Function() onConfirm;
  final Map<String, Object?> Function()? readValue;
  final void Function(int baseOffset, int extentOffset)? onSelection;
  final bool Function()? isActive;
  int revision = 0;
}

class PhoneKeyboardSession {
  PhoneKeyboardSession(
      {this.idleTimeout = const Duration(minutes: 10),
      String? accessToken,
      this.port = 0,
      this.expiresAt,
      this.onClosed,
      this.onConnected,
      this.onPresenceChanged,
      this.presenceTimeout = const Duration(seconds: 12),
      this.remoteState,
      this.dispatchRemote})
      : token = accessToken ?? _randomId();
  final Duration idleTimeout;
  final int port;
  final DateTime? expiresAt;
  final String sessionId = _randomId();
  final void Function()? onClosed;
  final void Function()? onConnected;
  final void Function()? onPresenceChanged;
  final Duration presenceTimeout;
  final Map<String, DateTime> _clients = {};
  Timer? _presenceTimer;
  bool _hasConnected = false;
  int get onlineCount => _clients.length;
  bool get clientConnected => onlineCount > 0;

  // Browser heartbeats, not short-lived HTTP sockets or remembered pairing.
  // Older pages have no browser ID: count them by LAN address until refreshed.
  void _heartbeat(HttpRequest request) {
    if (_closed) return;
    final id = request.headers.value('X-Kazumi-Client');
    if (id != null && !RegExp(r'^[a-zA-Z0-9_-]{16,64}$').hasMatch(id)) return;
    final key = id ?? 'legacy:${request.connectionInfo?.remoteAddress.address}';
    if (!_clients.containsKey(key) && _clients.length >= 64) return;
    final added = !_clients.containsKey(key);
    _clients[key] = DateTime.now().add(presenceTimeout);
    _schedulePresence();
    if (!_hasConnected) {
      _hasConnected = true;
      onConnected?.call();
    }
    if (added) onPresenceChanged?.call();
  }

  void _schedulePresence() {
    _presenceTimer?.cancel();
    if (_clients.isEmpty || _closed) return;
    final first = _clients.values.reduce((a, b) => a.isBefore(b) ? a : b);
    _presenceTimer = Timer(first.difference(DateTime.now()), () {
      final before = onlineCount;
      final now = DateTime.now();
      _clients.removeWhere((_, expiry) => !now.isBefore(expiry));
      if (before != onlineCount) onPresenceChanged?.call();
      _schedulePresence();
    });
  }

  final Map<String, Object?> Function()? remoteState;
  final Future<bool> Function(String, {required int revision})? dispatchRemote;
  final String token;
  HttpServer? _server;
  Timer? _idle;
  bool _closed = false;
  PhoneKeyboardTarget? _target;
  int _generation = 0;
  final Map<String, String> _receipts = {};
  final Map<String, Future<int>> _remoteResults = {};
  bool _remoteBusy = false;
  DateTime? _lastRemote;
  int _remoteSequence = 0;
  void invalidateRemoteRequests() {
    _remoteSequence++;
  }

  bool _readTextAllowed = false;
  bool get readTextAllowed => _readTextAllowed;
  void setReadTextAllowed(bool value) {
    if (_closed || value == _readTextAllowed) return;
    _readTextAllowed = value;
    _generation++;
  }

  Uri? uri;
  bool get isClosed => _closed;
  void setTarget(PhoneKeyboardTarget? target) {
    if (identical(target, _target)) return;
    _target = target;
    _generation++;
  }

  Map<String, Object?> get state => {
        'connected': !_closed,
        'onlineCount': onlineCount,
        'sessionId': sessionId,
        'pairingExpiresAt': expiresAt?.toUtc().toIso8601String(),
        'generation': _generation,
        'readTextAllowed': _readTextAllowed && _target?.writeOnly != true,
        'remoteSequence': _remoteSequence,
        'remote': remoteState?.call() ??
            {'context': '', 'revision': 0, 'keys': <Object>[]},
        'target': _target == null || _target!.isActive?.call() == false
            ? null
            : {
                'id': _target!.id,
                'label': _target!.label,
                'revision': _target!.revision,
                'maxLength': _target!.maxLength,
                'writeOnly': _target!.writeOnly,
                if (_readTextAllowed && !_target!.writeOnly)
                  ...?_target!.readValue?.call(),
              },
      };

  void _remember(String id, String fingerprint) {
    _receipts[id] = fingerprint;
    if (_receipts.length > 128) {
      final oldest = _receipts.keys.first;
      _receipts.remove(oldest);
      _remoteResults.remove(oldest);
    }
  }

  Future<int> _remote(
      Map<String, dynamic> data, String id, String fingerprint) async {
    final snapshot = remoteState?.call();
    final key = data['key'];
    final revision = data['remoteRevision'];
    final keys = snapshot?['keys'];
    if (_closed ||
        dispatchRemote == null ||
        key is! String ||
        revision is! int ||
        data['remoteSequence'] != _remoteSequence + 1 ||
        revision != snapshot?['revision'] ||
        keys is! List ||
        !keys.any((value) => value is Map && value['id'] == key)) return 409;
    final now = DateTime.now();
    if (_remoteBusy ||
        (_lastRemote != null &&
            now.difference(_lastRemote!) < const Duration(milliseconds: 120)))
      return 429;
    _remoteBusy = true;
    _remoteSequence++;
    _lastRemote = now;
    _remember(id, fingerprint);
    final receipt = Completer<int>();
    _remoteResults[id] = receipt.future;
    // A timed-out dispatch stays locked until it actually settles. Never queue
    // a second action behind an uncertain first action or retry it automatically.
    final dispatch =
        Future<bool>.sync(() => dispatchRemote!(key, revision: revision))
            .catchError((Object _) => false)
            .whenComplete(() => _remoteBusy = false);
    final status = await dispatch
        .then((ok) => ok ? 200 : 409)
        .timeout(const Duration(seconds: 2), onTimeout: () => 504);
    receipt.complete(status);
    if (!_closed && status == 200) _touch();
    return status;
  }

  void _touch() {
    _idle?.cancel();
    _idle = Timer(expiresAt?.difference(DateTime.now()) ?? idleTimeout, close);
  }

  Future<Uri> start({InternetAddress? address}) async {
    if (_closed || _server != null) throw StateError('Session already used');
    if (expiresAt != null && !DateTime.now().isBefore(expiresAt!)) {
      throw StateError('Pairing expired');
    }
    var selected = address;
    if (selected == null) {
      for (final interface
          in await NetworkInterface.list(type: InternetAddressType.IPv4)) {
        for (final candidate in interface.addresses) {
          final b = candidate.rawAddress;
          if (b[0] == 10 ||
              (b[0] == 172 && b[1] >= 16 && b[1] <= 31) ||
              (b[0] == 192 && b[1] == 168)) {
            selected = candidate;
            break;
          }
        }
        if (selected != null) break;
      }
    }
    if (selected == null) throw StateError('No private LAN address');
    final server = await HttpServer.bind(selected, port);
    if (_closed) {
      await server.close(force: true);
      throw StateError('Closed');
    }
    _server = server;
    uri = Uri(
        scheme: 'http',
        host: selected.address,
        port: server.port,
        path: '/$token');
    _touch();
    server.listen(_handle);
    return uri!;
  }

  Future<void> _handle(HttpRequest request) async {
    final response = request.response;
    StreamSubscription<List<int>>? bodySubscription;
    Timer? bodyTimer;
    response.persistentConnection = false;
    response.headers.set('Cache-Control', 'no-store');
    response.headers.set('Referrer-Policy', 'same-origin');
    response.headers.set('X-Content-Type-Options', 'nosniff');
    response.headers.set('Content-Security-Policy',
        "default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; connect-src 'self'; frame-ancestors 'none'");
    try {
      if (_closed ||
          (expiresAt != null && !DateTime.now().isBefore(expiresAt!)) ||
          !['/$token', '/$token/state', '/$token/input']
              .contains(request.uri.path)) {
        response.statusCode = 404;
      } else if (request.headers.value('origin') != null &&
          request.headers.value('origin') != uri!.origin) {
        response.statusCode = 403;
      } else if (request.method == 'GET' && request.uri.path == '/$token') {
        response.headers.contentType = ContentType.html;
        response.write(_page);
      } else if (request.method == 'GET' &&
          request.uri.path == '/$token/state') {
        _heartbeat(request);
        response.headers.contentType = ContentType.json;
        response
            .write(jsonEncode(state)); // Polling does not extend idle lifetime.
      } else if (request.method == 'POST' &&
          request.uri.path == '/$token/input') {
        final bytes = <int>[];
        final body = Completer<void>();
        void reject(Object error) {
          if (!body.isCompleted) body.completeError(error);
        }

        bodyTimer = Timer(const Duration(seconds: 5),
            () => reject(TimeoutException('Input deadline')));
        bodySubscription = request.listen(
            (chunk) {
              if (bytes.length + chunk.length > 16384) {
                reject(const FormatException('Too large'));
              } else {
                bytes.addAll(chunk);
              }
            },
            onError: reject,
            onDone: () {
              if (!body.isCompleted) body.complete();
            });
        await body.future;
        bodyTimer.cancel();
        final data = jsonDecode(utf8.decode(bytes));
        if (data is! Map<String, dynamic>) {
          throw const FormatException('Invalid request');
        }
        final requestId = data['requestId'];
        if (requestId is! String ||
            requestId.isEmpty ||
            requestId.length > 96) {
          throw const FormatException('Invalid id');
        }
        if (data.containsKey('selection') &&
            data['action'] != 'input' &&
            data['action'] != 'selection') {
          throw const FormatException('Selection is not valid for this action');
        }
        final fingerprint = jsonEncode(data);
        if (_closed ||
            (expiresAt != null &&
                (!DateTime.now().isBefore(expiresAt!) ||
                    data['sessionId'] != sessionId))) {
          response.statusCode = 409;
        } else if (_receipts.containsKey(requestId)) {
          response.statusCode = _receipts[requestId] == fingerprint
              ? await (_remoteResults[requestId] ?? Future.value(200))
              : 409;
        } else if (data['action'] == 'remote') {
          response.statusCode = await _remote(data, requestId, fingerprint);
        } else {
          final target = _target;
          if (_closed ||
              target == null ||
              target.isActive?.call() == false ||
              data['targetId'] != target.id ||
              data['generation'] != _generation ||
              data['revision'] != target.revision) {
            response.statusCode = 409;
          } else {
            final action = data['action'];
            final text = data['text'];
            if (!['input', 'clear', 'confirm', 'selection'].contains(action) ||
                (action == 'input' &&
                    (text is! String ||
                        text.runes.length > target.maxLength ||
                        text.contains(
                            RegExp(r'[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]'))))) {
              throw const FormatException('Invalid input');
            }
            final selection = data['selection'];
            final selectionOnly = action == 'selection';
            if (selectionOnly && selection == null)
              throw const FormatException('Missing selection');
            if (selection != null) {
              // Reject before readValue: selection must not inspect credentials.
              if (target.writeOnly) {
                throw const FormatException('Write-only target');
              }
              final value =
                  action == 'input' ? text : target.readValue?.call()['text'];
              if (!_readTextAllowed ||
                  target.onSelection == null ||
                  selection is! Map ||
                  value is! String ||
                  selection['baseOffset'] is! int ||
                  selection['extentOffset'] is! int ||
                  (selection['baseOffset'] as int) < 0 ||
                  (selection['extentOffset'] as int) < 0 ||
                  (selection['baseOffset'] as int) > value.length ||
                  (selection['extentOffset'] as int) > value.length) {
                throw const FormatException('Invalid selection');
              }
            }
            // Record before callbacks: synchronous route changes cannot replay effects.
            _remember(requestId, fingerprint);
            target.revision++;
            if (action == 'confirm') {
              target.onConfirm();
            } else if (!selectionOnly) {
              target.onText(action == 'clear' ? '' : text as String);
            }
            if (selection != null)
              target.onSelection!(selection['baseOffset'] as int,
                  selection['extentOffset'] as int);
            _touch();
          }
        }
        if (response.statusCode == 200) _heartbeat(request);
        response.headers.contentType = ContentType.json;
        response.write(jsonEncode(state));
      } else {
        response.statusCode = 405;
      }
    } on Object {
      response.statusCode = 400;
    } finally {
      bodyTimer?.cancel();
      try {
        await response.close();
      } on Object {/* disconnected */}
      await bodySubscription?.cancel();
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _idle?.cancel();
    _presenceTimer?.cancel();
    _clients.clear();
    _target = null;
    _readTextAllowed = false;
    await _server?.close(force: true);
    _receipts.clear();
    _remoteResults.clear();
    onClosed?.call();
  }
}

const _page = r'''<!doctype html>
<html lang="zh"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover"><meta name="color-scheme" content="light dark"><title>Kazumi · 手机遥控</title>
<style>
*{box-sizing:border-box}
:root{color-scheme:light;--background:#f7faef;--surface:#eef2e6;--onSurface:#191d17;--muted:#42493d;--primary:#3e6838;--onPrimary:#ffffff;--secondary:#dfead7;--onSecondary:#172114;--outline:#c3cbbd}
body{font:16px/1.5 system-ui,-apple-system,"Segoe UI",sans-serif;margin:0 auto;padding:20px 16px max(24px,env(safe-area-inset-bottom));max-width:520px;background:var(--background);color:var(--onSurface);overflow-wrap:anywhere}
[hidden]{display:none!important}h1{font-size:24px;font-weight:650;letter-spacing:-.5px;margin:0}h2{font-size:15px;margin:24px 0 12px}p{margin:10px 0;color:var(--muted);font-size:13px}.brand{display:flex;align-items:center;gap:12px}.mark{display:grid;place-items:center;width:44px;height:44px;border-radius:16px;background:var(--primary);color:var(--onPrimary);font-size:24px;font-weight:700}.eyebrow{font-size:11px;letter-spacing:2px;text-transform:uppercase}.subtitle{margin:0;font-size:13px}
#status{padding:10px 14px;background:var(--surface);border-radius:12px;margin:20px 0 14px;min-height:40px}.modes{display:grid;grid-template-columns:1fr 1fr;gap:4px;padding:4px;background:var(--surface);border-radius:28px;margin-bottom:20px}
button,textarea{font:inherit;min-width:0;max-width:100%;border:1px solid var(--outline);color:var(--onSurface);background:var(--surface)}button{min-height:48px;padding:10px 12px;border-radius:16px;margin:0;cursor:pointer;touch-action:manipulation;white-space:normal;overflow-wrap:anywhere;transition:background .12s,transform .12s}button:active:not(:disabled){transform:scale(.96)}button:focus-visible,a:focus-visible,textarea:focus-visible{outline:3px solid var(--primary);outline-offset:3px}button:disabled{opacity:.4;cursor:default}.modes button{border:0;border-radius:24px;background:transparent}.modes button[aria-pressed="true"]{background:var(--primary);color:var(--onPrimary)}
textarea{display:block;width:100%;border-radius:20px;padding:16px;resize:vertical;min-height:140px}#confirm{background:var(--primary);color:var(--onPrimary);border:0}.editActions{display:flex;gap:8px;margin:12px 0}.editActions button{flex:1}#privacy{margin-bottom:14px}
#remoteKeys{display:flex;flex-direction:column}#remoteDpad{order:0}#remoteBack{order:1}#remoteKeys>h2{order:3}#remoteExtras{order:4}#remoteKeys>p{order:5}#remoteKeys>details{order:6}#remotePanel[data-numbers="true"] details{order:2}
#remoteStatus{text-align:center;margin:0 0 14px;font-size:13px}#remoteDpad{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));grid-template-areas:". up ." "left ok right" ". down .";gap:6px;width:100%;max-width:320px;aspect-ratio:1;margin:0 auto;padding:18px;border-radius:50%;background:var(--surface);border:1px solid var(--outline)}#remoteDpad button{padding:4px;border:0;border-radius:50%;font-size:24px;background:transparent}#remoteDpad [data-key="ok"]{font-size:16px;font-weight:650;background:var(--primary);color:var(--onPrimary)}#remoteBack{display:grid;grid-template-columns:minmax(0,1fr);gap:8px;width:100%;margin:16px auto 0;max-width:320px}#remoteBack button{border:0;background:var(--secondary);color:var(--onSecondary)}
#remoteExtras,#remoteDigits{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:8px}#remoteExtras button{font-size:13px;min-height:52px}#remoteExtras [data-key="playPause"]{grid-column:1/-1;background:var(--primary);color:var(--onPrimary);border:0;font-size:16px}#remoteExtras [data-key="red"]{border-bottom:4px solid #bd4141}#remoteExtras [data-key="green"]{border-bottom:4px solid #5a8c49}#remoteExtras [data-key="yellow"]{border-bottom:4px solid #b48b23}#remoteExtras [data-key="blue"]{border-bottom:4px solid #4d7caf}#remoteDigits button{font-size:22px;min-height:54px}#remoteDigits [data-key="digit0"]{grid-column:2;grid-row:4}#remoteExtras:empty,#remoteBack:empty{display:none}
details{margin-top:20px;border:1px solid var(--outline);border-radius:20px;padding:14px}summary{cursor:pointer;font-size:15px;font-weight:600}details p{margin:8px 0 14px}footer{margin-top:24px;text-align:center}footer p{font-size:11px}a{color:var(--primary)}
@media(prefers-reduced-motion:reduce){button{transition:none}}
</style></head><body>
<header class="brand"><div class="mark" aria-hidden="true">K</div><div><div class="eyebrow">Kazumi TV</div><h1>手机控制</h1><p class="subtitle">把遥控器放在手边</p></div></header>
<p id="status" role="status">连接中…</p>
<div class="modes" role="group" aria-label="控制方式"><button id="remoteMode" aria-pressed="true">遥控器</button><button id="keyboardMode" aria-pressed="false">文字输入</button></div>
<section id="keyboardPanel" hidden><p id="privacy">默认仅替换草稿，不读取电视已有文本。可在电视连接弹窗授权本次读取普通文本。</p><textarea id="text" aria-label="发送到电视的文本" rows="5" disabled></textarea><div class="editActions"><button id="clear" disabled>清空</button><button id="confirm" disabled>确认文本</button></div><p>确认只保存文本；搜索、下载等操作请在电视上确认。</p></section>
<section id="remotePanel"><p id="remoteStatus"></p><div id="remoteKeys"><div id="remoteDpad" role="group" aria-label="方向键"></div><div id="remoteBack" role="group" aria-label="返回"></div><h2>播放与功能</h2><div id="remoteExtras" role="group" aria-label="当前场景其他操作"></div><p>灰色按键在当前页面不可用，进入播放器后自动更新。</p><details open><summary>节目编号</summary><p id="digitStatus">返回首页后可按海报编号选番。</p><div id="remoteDigits" role="group" aria-label="数字键"></div></details></div></section>
<footer><button id="hapticToggle" type="button" aria-pressed="true">按键震动：开</button><p id="connectionPolicy">临时连接 · 闲置 10 分钟或电视应用进入后台后断开</p><p>电源、电视桌面与系统音量请使用实体遥控器</p></footer><script>
let state=null, composing=false, busy=false, dirty=false, serial=0, uncertain=false, deferred=null, compositionTarget=null, compositionRevision=null, discardComposition=false, offline=false, selectionDirty=false, remoteMessage='', sending=false;
const base=location.pathname.replace(/\/$/,''), box=document.getElementById('text'), status=document.getElementById('status'), clear=document.getElementById('clear'), confirm=document.getElementById('confirm');
let haptics=true, failures=0, nextPollAt=0;
try{haptics=localStorage.getItem('kazumi-haptics')!=='off';}catch(_){}
const hapticButton=document.getElementById('hapticToggle');
function hapticAvailable(){return typeof navigator!=='undefined'&&typeof navigator.vibrate==='function';}
function renderHaptics(){hapticButton.disabled=!hapticAvailable();hapticButton.textContent=hapticAvailable()?'按键震动：'+(haptics?'开':'关'):'此浏览器不支持按键震动';hapticButton.setAttribute('aria-pressed',String(haptics&&hapticAvailable()));}
function pulse(){if(haptics&&hapticAvailable()&&document.visibilityState!=='hidden'){try{navigator.vibrate(12);}catch(_){}}}
hapticButton.onclick=()=>{haptics=!haptics;try{localStorage.setItem('kazumi-haptics',haptics?'on':'off');}catch(_){}renderHaptics();if(haptics)pulse();};renderHaptics();
const client=Date.now().toString(36)+Math.random().toString(36).slice(2);
let browserId=client;try{const saved=localStorage.getItem('kazumi-remote-browser');if(saved&&/^[a-zA-Z0-9_-]{16,64}$/.test(saved))browserId=saved;else localStorage.setItem('kazumi-remote-browser',browserId);}catch(_){}
function key(s){return s?.target ? (s.sessionId||'')+':'+s.generation+':'+s.target.id : (s?.sessionId||null);}
function selection(){return {baseOffset:box.selectionDirection==='backward'?box.selectionEnd:box.selectionStart,extentOffset:box.selectionDirection==='backward'?box.selectionStart:box.selectionEnd};}
function sameSelection(a,b){return a?.baseOffset===b?.baseOffset&&a?.extentOffset===b?.extentOffset;}
function canRead(s){return !!s?.readTextAllowed&&!s.target?.writeOnly;}
async function request(url,options={}){const controller=new AbortController();const timer=setTimeout(()=>controller.abort(),5000);try{const response=await fetch(url,{...options,headers:{...options.headers,'X-Kazumi-Client':browserId},signal:controller.signal});const data=await response.json();return {ok:response.ok,status:response.status,json:async()=>data};}finally{clearTimeout(timer);}}
function setText(element,text){if(element.textContent!==text)element.textContent=text;}
function render(){const expiry=state?.pairingExpiresAt;setText(document.getElementById('connectionPolicy'),expiry?'配对有效至 '+new Date(expiry).toLocaleString()+' · 可收藏本页；电视应用回到前台后自动重连':'临时连接 · 闲置 10 分钟或电视应用进入后台后断开');const t=state?.target;box.disabled=!t||offline;clear.disabled=!t||offline||sending||composing;confirm.disabled=!t||offline||sending||composing||uncertain;if(t)box.maxLength=t.maxLength;setText(status,offline?'连接已断开或网络不可达，请等待重连或在电视上重新开启':uncertain?'电视内容已变化或上次发送未确认，请检查后重新输入或清空':t?'正在编辑：'+t.label:'已连接 · 可遥控电视，或打开输入框输入文字');setText(document.getElementById('privacy'),t?.writeOnly?'凭据只写：可粘贴新内容；电视已有内容始终不回读。确认后请在电视验证并保存。':canRead(state)?'本次已允许读取普通文本，可编辑原文与选择区；断开即撤销。':'仅替换草稿，不读取电视已有文本。可在电视连接弹窗授权本次读取。');const remote=state?.remote;setText(document.getElementById('remoteStatus'),remoteMessage||('当前场景：'+(remote?.context||'无可用操作')));renderRemote(remote);}
const remoteButtons=new Map();
const fixedExtras=[['playPause','播放 / 暂停'],['play','播放'],['pause','暂停'],['stop','停止'],['rewind','快退'],['fastForward','快进'],['previous','上一集'],['next','下一集'],['guide','选集'],['menu','Menu 菜单'],['info','Info 信息'],['red','红键'],['green','绿键'],['yellow','黄键'],['blue','蓝键']];
function applyTheme(theme){if(!theme)return;const root=document.documentElement;for(const name of ['background','surface','onSurface','muted','primary','onPrimary','secondary','onSecondary','outline']){const value=theme[name];if(typeof value==='string'&&/^#[0-9a-f]{6}$/i.test(value))root.style.setProperty('--'+name,value);}if(['light','dark'].includes(theme.brightness))root.style.colorScheme=theme.brightness;}
function renderRemote(remote){applyTheme(remote?.theme);document.getElementById('remotePanel').setAttribute('data-numbers',String((remote?.keys||[]).some(item=>/^digit[0-9]$/.test(item.id))));setText(document.getElementById('digitStatus'),(remote?.keys||[]).some(item=>/^digit[0-9]$/.test(item.id))?(remote.numberHint||'LCN 频道编号：按数字选择当前频道。'):'当前页面不接受节目编号；返回首页可按海报编号选番。');const offered=new Map((remote?.keys||[]).map(item=>[item.id,item]));const items=[...['up','left','ok','right','down','back'].filter(id=>offered.has(id)).map(id=>offered.get(id)),...fixedExtras.map(([id,label])=>({id,label})),...[1,2,3,4,5,6,7,8,9,0].map(i=>({id:'digit'+i,label:String(i)})),...(remote?.keys||[]).filter(item=>!['up','left','ok','right','down','back',...fixedExtras.map(x=>x[0])].includes(item.id)&&!/^digit[0-9]$/.test(item.id))];
for(const item of items){let button=remoteButtons.get(item.id);if(!button){button=document.createElement('button');button.dataset.key=item.id;button.onclick=()=>{if(!button.disabled)sendRemote(item.id,state?.remote?.revision);};remoteButtons.set(item.id,button);let area='remoteExtras';if(['up','left','ok','right','down'].includes(item.id)){area='remoteDpad';button.style.gridArea=item.id;}else if(item.id==='back')area='remoteBack';else if(/^digit[0-9]$/.test(item.id))area='remoteDigits';document.getElementById(area).appendChild(button);}const capability=offered.get(item.id);const arrows={up:'↑',down:'↓',left:'←',right:'→',ok:'OK'};const label=arrows[item.id]||(capability?(['red','green','yellow','blue'].includes(item.id)?item.label+' · '+capability.label:capability.label):item.label);if(button.textContent!==label)button.textContent=label;button.setAttribute('aria-label',capability?.label||item.label);button.title=capability?capability.label:'当前页面未提供此操作';button.disabled=!capability||offline||sending||composing||dirty;button.hidden=false;}
for(const [id,button] of remoteButtons){if(!items.some(item=>item.id===id))button.hidden=true;}}

function applyValue(s){const t=s.target;if(canRead(s)&&typeof t?.text==='string'){box.value=t.text;const sel=t.selection;if(sel)box.setSelectionRange(Math.min(sel.baseOffset,sel.extentOffset),Math.max(sel.baseOffset,sel.extentOffset),sel.baseOffset>sel.extentOffset?'backward':'forward');}else box.value='';}
function update(s,ack=false){if(composing){deferred={s,ack};return;}const changed=key(state)!==key(s),revisionChanged=state?.target?.revision!==s.target?.revision;state=s;if(changed){dirty=false;selectionDirty=false;uncertain=false;applyValue(s);}else if(!ack&&revisionChanged&&(dirty||selectionDirty)){dirty=false;selectionDirty=false;uncertain=true;}else if(!dirty&&!selectionDirty&&canRead(s)&&(revisionChanged||ack)){applyValue(s);}render();}
async function poll(){if(busy||document.visibilityState==='hidden')return;busy=true;try{const r=await request(base+'/state');if(!r.ok)throw Error();const s=await r.json();offline=false;failures=0;nextPollAt=0;update(s);}catch(e){offline=true;uncertain=true;nextPollAt=Date.now()+Math.min(15000,1000*Math.pow(2,Math.min(++failures,4)));}finally{busy=false;sending=false;render();}}
async function send(action){if(busy||composing||offline||!state?.target||(action==='confirm'&&uncertain))return false;busy=true;sending=true;render();const t=state.target,payload={sessionId:state.sessionId,requestId:client+'-'+(++serial),targetId:t.id,generation:state.generation,revision:t.revision,action,text:box.value};if(canRead(state)&&(action==='input'||action==='selection'))payload.selection=selection();try{const r=await request(base+'/input',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(payload)});const s=await r.json();if(!r.ok){dirty=false;selectionDirty=false;uncertain=true;update(s);return false;}dirty=box.value!==payload.text;selectionDirty=!!payload.selection&&!sameSelection(selection(),payload.selection);if(action!=='confirm')uncertain=false;update(s,true);return true;}catch(e){dirty=false;selectionDirty=false;uncertain=true;offline=true;return false;}finally{busy=false;sending=false;render();}}
async function sendRemote(id,revision){if(busy||composing||offline||dirty||state?.remote?.revision!==revision)return false;pulse();busy=true;sending=true;render();const payload={sessionId:state.sessionId,requestId:client+'-'+(++serial),action:'remote',key:id,remoteRevision:revision,remoteSequence:(state.remoteSequence||0)+1};try{const r=await request(base+'/input',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(payload)});const s=await r.json();remoteMessage=r.ok?'':r.status===429?'按键过快，请稍后再按；不会自动重试':'场景已变化或操作未确认，请查看电视';update(s);return r.ok;}catch(e){offline=true;remoteMessage='操作结果未确认，请先查看电视；不会重发';return false;}finally{busy=false;sending=false;render();}}
box.addEventListener('compositionstart',()=>{composing=true;compositionTarget=key(state);compositionRevision=state?.target?.revision;render();});
box.addEventListener('compositionend',()=>{composing=false;const next=deferred;deferred=null;const conflict=next&&(key(next.s)!==compositionTarget||(!next.ack&&next.s.target?.revision!==compositionRevision));if(conflict){dirty=false;selectionDirty=false;update(next.s);applyValue(next.s);uncertain=true;discardComposition=true;render();return;}dirty=true;if(next)update(next.s,next.ack);if(compositionTarget!==key(state)){dirty=false;discardComposition=true;render();return;}send('input');});
box.addEventListener('input',()=>{if(composing)return;if(discardComposition){discardComposition=false;applyValue(state);dirty=false;render();return;}dirty=true;send('input');});
box.addEventListener('select',()=>{if(composing||!canRead(state)||sameSelection(selection(),state?.target?.selection))return;selectionDirty=true;if(!dirty)send('selection');});
clear.onclick=()=>{if(busy||composing)return;box.value='';dirty=true;send('clear');};
confirm.onclick=async()=>{if(busy||composing||uncertain||!state?.target)return;const target=key(state);if(dirty&&!(await send('input')))return;if(selectionDirty&&!(await send('selection')))return;if(!dirty&&!uncertain&&key(state)===target)await send('confirm');};
function showMode(keyboard){document.getElementById('keyboardPanel').hidden=!keyboard;document.getElementById('remotePanel').hidden=keyboard;document.getElementById('keyboardMode').setAttribute('aria-pressed',String(keyboard));document.getElementById('remoteMode').setAttribute('aria-pressed',String(!keyboard));}
document.getElementById('keyboardMode').onclick=()=>showMode(true);document.getElementById('remoteMode').onclick=()=>showMode(false);
document.addEventListener?.('visibilitychange',()=>{if(document.visibilityState!=='hidden'){nextPollAt=0;poll();}});
setInterval(()=>{if(document.visibilityState==='hidden'||Date.now()<nextPollAt)return;if(dirty&&!busy&&!composing&&!uncertain)send('input');else if(selectionDirty&&!busy&&!composing&&!uncertain)send('selection');else poll();},800);poll();
</script></body></html>''';
