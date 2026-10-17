import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

String _randomId() => List.generate(16, (_) => Random.secure().nextInt(256))
    .map((v) => v.toRadixString(16).padLeft(2, '0'))
    .join();

/// Only an explicitly opened, non-sensitive editor may own a target.
/// Existing field contents never leave the TV, including credential-bearing URLs.
class PhoneKeyboardTarget {
  PhoneKeyboardTarget(
      {required this.label,
      required this.onText,
      required this.onConfirm,
      this.isActive,
      this.maxLength = 2048});
  final String id = _randomId();
  final String label;
  final int maxLength;
  final void Function(String) onText;
  final void Function() onConfirm;
  final bool Function()? isActive;
  int revision = 0;
}

class PhoneKeyboardSession {
  PhoneKeyboardSession(
      {this.idleTimeout = const Duration(minutes: 10), this.onClosed});
  final Duration idleTimeout;
  final void Function()? onClosed;
  final String token = _randomId();
  HttpServer? _server;
  Timer? _idle;
  bool _closed = false;
  PhoneKeyboardTarget? _target;
  int _generation = 0;
  final Map<String, String> _receipts = {};
  Uri? uri;
  bool get isClosed => _closed;
  void setTarget(PhoneKeyboardTarget? target) {
    if (identical(target, _target)) return;
    _target = target;
    _generation++;
  }

  Map<String, Object?> get state => {
        'connected': !_closed,
        'generation': _generation,
        'target': _target == null || _target!.isActive?.call() == false
            ? null
            : {
                'id': _target!.id,
                'label': _target!.label,
                'revision': _target!.revision,
                'maxLength': _target!.maxLength,
              },
      };
  void _touch() {
    _idle?.cancel();
    _idle = Timer(idleTimeout, close);
  }

  Future<Uri> start({InternetAddress? address}) async {
    if (_closed || _server != null) throw StateError('Session already used');
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
    final server = await HttpServer.bind(selected, 0);
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
        final fingerprint = jsonEncode(data);
        if (_receipts.containsKey(requestId)) {
          response.statusCode = _receipts[requestId] == fingerprint ? 200 : 409;
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
            if (!['input', 'clear', 'confirm'].contains(action) ||
                (action == 'input' &&
                    (text is! String ||
                        text.runes.length > target.maxLength ||
                        text.contains(
                            RegExp(r'[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]'))))) {
              throw const FormatException('Invalid input');
            }
            // Record before callbacks: synchronous route changes cannot replay effects.
            _receipts[requestId] = fingerprint;
            if (_receipts.length > 128) _receipts.remove(_receipts.keys.first);
            target.revision++;
            if (action == 'confirm') {
              target.onConfirm();
            } else {
              target.onText(action == 'clear' ? '' : text as String);
            }
            _touch();
          }
        }
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
    _target = null;
    await _server?.close(force: true);
    _receipts.clear();
    onClosed?.call();
  }
}

const _page =
    r'''<!doctype html><html lang="zh"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>KazumiTV 手机键盘</title><body style="font:20px sans-serif;padding:20px"><h1>手机键盘</h1><p id="status">连接中…</p><p>请在电视上按 OK 打开要编辑的普通输入框。已有内容不会发送到手机。输入将替换电视草稿。</p><textarea id="text" rows="5" style="width:100%" disabled></textarea><p><button id="clear" disabled>清空</button> <button id="confirm" disabled>确认文本</button></p><p>确认仅保存文本；搜索、下载等操作请在电视上执行。闲置 10 分钟自动断开，可在电视上重新开启。</p><script>
let state=null, composing=false, busy=false, dirty=false, serial=0, uncertain=false, deferred=null, compositionTarget=null, discardComposition=false, offline=false;
const base=location.pathname.replace(/\/$/,''), box=document.getElementById('text'), status=document.getElementById('status'), clear=document.getElementById('clear'), confirm=document.getElementById('confirm');
const client=Date.now().toString(36)+Math.random().toString(36).slice(2);
function key(s){return s?.target ? s.generation+':'+s.target.id : null;}
async function request(url,options={}){const controller=new AbortController();const timer=setTimeout(()=>controller.abort(),5000);try{const response=await fetch(url,{...options,signal:controller.signal});const data=await response.json();return {ok:response.ok,json:async()=>data};}finally{clearTimeout(timer);}}
function render(){const t=state?.target;box.disabled=!t||offline;clear.disabled=!t||offline||busy||composing;confirm.disabled=!t||offline||busy||composing||uncertain; if(t)box.maxLength=t.maxLength;status.textContent=offline?'连接已断开或网络不可达，请等待重连或在电视重新开启':uncertain?'上次发送未确认，请重新输入或清空后再确认':t?'正在编辑：'+t.label:'已连接，等待电视打开输入框';}
function update(s){if(composing){deferred=s;return;}const changed=key(state)!==key(s);state=s;if(changed){box.value='';dirty=false;uncertain=false;}render();}
async function poll(){if(busy||composing)return;busy=true;render();try{const r=await request(base+'/state');if(!r.ok)throw Error();const s=await r.json();offline=false;update(s);}catch(e){offline=true;uncertain=true;status.textContent='连接已断开或网络不可达，请在电视上重新连接';box.disabled=clear.disabled=confirm.disabled=true;}finally{busy=false;if(state)render();}}
async function send(action){if(busy||composing||offline||!state?.target||(action==='confirm'&&uncertain))return false;busy=true;render();const t=state.target;const payload={requestId:client+'-'+(++serial),targetId:t.id,generation:state.generation,revision:t.revision,action,text:box.value};try{const r=await request(base+'/input',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(payload)});const s=await r.json();if(!r.ok){dirty=false;uncertain=true;update(s);return false;}dirty=box.value!==payload.text;if(action!=='confirm')uncertain=false;update(s);return true;}catch(e){dirty=false;uncertain=true;offline=true;return false;}finally{busy=false;render();}}
box.addEventListener('compositionstart',()=>{composing=true;compositionTarget=key(state);render();});
box.addEventListener('compositionend',()=>{composing=false;const next=deferred;deferred=null;if(next)update(next);if(compositionTarget!==key(state)){box.value='';dirty=false;discardComposition=true;render();return;}dirty=true;send('input');});
box.addEventListener('input',()=>{if(composing)return;if(discardComposition){discardComposition=false;box.value='';dirty=false;render();return;}dirty=true;send('input');});
clear.onclick=()=>{if(busy||composing)return;box.value='';dirty=true;send('clear');};
confirm.onclick=async()=>{if(busy||composing||uncertain||!state?.target)return;const target=key(state);if(dirty&&!(await send('input')))return;if(!dirty&&!uncertain&&key(state)===target)await send('confirm');};
setInterval(()=>{if(dirty&&!busy&&!composing&&!uncertain)send('input');else poll();},800);poll();
</script></body></html>''';
