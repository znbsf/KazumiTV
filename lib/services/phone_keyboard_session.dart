import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

String _randomId() => List.generate(16, (_) => Random.secure().nextInt(256))
    .map((v) => v.toRadixString(16).padLeft(2, '0'))
    .join();

/// Only an explicitly opened, non-sensitive editor may own a target.
/// Existing contents are exposed only with explicit, session-scoped TV consent.
class PhoneKeyboardTarget {
  PhoneKeyboardTarget(
      {required this.label,
      required this.onText,
      required this.onConfirm,
      this.readValue,
      this.onSelection,
      this.isActive,
      this.maxLength = 2048});
  final String id = _randomId();
  final String label;
  final int maxLength;
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
      this.onClosed,
      this.onConnected,
      this.remoteState,
      this.dispatchRemote});
  final Duration idleTimeout;
  final void Function()? onClosed;
  final void Function()? onConnected;
  bool _clientConnected = false;
  bool get clientConnected => _clientConnected;
  final Map<String, Object?> Function()? remoteState;
  final Future<bool> Function(String, {required int revision})? dispatchRemote;
  final String token = _randomId();
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
        'generation': _generation,
        'readTextAllowed': _readTextAllowed,
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
                if (_readTextAllowed) ...?_target!.readValue?.call(),
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
        if (!_clientConnected) {
          _clientConnected = true;
          onConnected?.call();
        }
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
        if (_receipts.containsKey(requestId)) {
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
    _readTextAllowed = false;
    await _server?.close(force: true);
    _receipts.clear();
    _remoteResults.clear();
    onClosed?.call();
  }
}

const _page =
    r'''<!doctype html><html lang="zh"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>KazumiTV 手机控制</title><style>*{box-sizing:border-box}body{font:18px sans-serif;margin:0 auto;padding:16px;max-width:640px;background:#15151d;color:#eee;overflow-wrap:anywhere}button,textarea{font:inherit;padding:12px;border-radius:12px;margin:0;min-width:0;max-width:100%}textarea{display:block;width:100%;background:#242430;color:#fff;resize:vertical}button{min-height:48px;background:#d0bcff;color:#251543;border:0;white-space:normal;overflow-wrap:anywhere}button:disabled{opacity:.45}a{color:#d0bcff}nav{line-height:2}#keyboardMode,#remoteMode{margin:0 4px 12px 0}#remoteDpad{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));grid-template-areas:". up ." "left ok right" ". down .";gap:8px;width:100%;max-width:320px;margin:0 auto}#remoteBack{display:grid;grid-template-columns:minmax(0,1fr);gap:8px;margin:16px 0}#remoteExtras,#remoteDigits{display:grid;grid-template-columns:repeat(auto-fit,minmax(88px,1fr));gap:8px}#remoteExtras:empty,#remoteBack:empty{display:none}</style><body><h1>手机控制</h1><p id="status">连接中…</p><button id="keyboardMode">键盘</button><button id="remoteMode">遥控</button><section id="keyboardPanel"><p id="privacy">默认仅替换草稿，不读取电视已有文本。可在电视连接弹窗授权本次读取普通文本。</p><textarea id="text" rows="5" disabled></textarea><p><button id="clear" disabled>清空</button><button id="confirm" disabled>确认文本</button></p><p>确认只保存文本；搜索、下载等业务操作仍由电视明确执行。</p></section><section id="remotePanel" hidden><nav aria-label="遥控分组"><a href="#remoteDpad">方向</a> · <a href="#remoteExtras">Info / Menu / 四色</a> · <a href="#remoteDigits">数字</a></nav><p id="remoteStatus"></p><div id="remoteKeys"><div id="remoteDpad" role="group" aria-label="方向键"></div><div id="remoteBack" role="group" aria-label="返回"></div><h2>功能键 · Info / Menu / 四色</h2><p>灰色按键表示当前页面未提供该操作；进入播放器后可用功能会自动更新。</p><div id="remoteExtras" role="group" aria-label="当前场景其他操作"></div><h2>LCN 数字键</h2><p id="digitStatus">LCN 数字键需要频道模式。</p><div id="remoteDigits" role="group" aria-label="数字键"></div></div><p>仅控制当前应用实际支持的操作，不控制系统电源、HOME 或系统音量。</p></section><p>临时局域网连接，闲置 10 分钟或电视应用进入后台自动断开。</p><script>
let state=null, composing=false, busy=false, dirty=false, serial=0, uncertain=false, deferred=null, compositionTarget=null, compositionRevision=null, discardComposition=false, offline=false, selectionDirty=false, remoteMessage='', sending=false;
const base=location.pathname.replace(/\/$/,''), box=document.getElementById('text'), status=document.getElementById('status'), clear=document.getElementById('clear'), confirm=document.getElementById('confirm');
const client=Date.now().toString(36)+Math.random().toString(36).slice(2);
function key(s){return s?.target ? s.generation+':'+s.target.id : null;}
function selection(){return {baseOffset:box.selectionDirection==='backward'?box.selectionEnd:box.selectionStart,extentOffset:box.selectionDirection==='backward'?box.selectionStart:box.selectionEnd};}
function sameSelection(a,b){return a?.baseOffset===b?.baseOffset&&a?.extentOffset===b?.extentOffset;}
async function request(url,options={}){const controller=new AbortController();const timer=setTimeout(()=>controller.abort(),5000);try{const response=await fetch(url,{...options,signal:controller.signal});const data=await response.json();return {ok:response.ok,status:response.status,json:async()=>data};}finally{clearTimeout(timer);}}
function setText(element,text){if(element.textContent!==text)element.textContent=text;}
function render(){const t=state?.target;box.disabled=!t||offline;clear.disabled=!t||offline||sending||composing;confirm.disabled=!t||offline||sending||composing||uncertain;if(t)box.maxLength=t.maxLength;setText(status,offline?'连接已断开或网络不可达，请等待重连或在电视上重新开启':uncertain?'电视内容已变化或上次发送未确认，请检查后重新输入或清空':t?'正在编辑：'+t.label:'已连接，等待电视打开输入框');setText(document.getElementById('privacy'),state?.readTextAllowed?'本次已允许读取普通文本，可编辑原文与选择区；断开即撤销。':'仅替换草稿，不读取电视已有文本。可在电视连接弹窗授权本次读取。');const remote=state?.remote;setText(document.getElementById('remoteStatus'),remoteMessage||('当前场景：'+(remote?.context||'无可用操作')));renderRemote(remote);}
const remoteButtons=new Map();
const fixedExtras=[['menu','Menu 菜单'],['info','Info 信息'],['red','红键'],['green','绿键'],['yellow','黄键'],['blue','蓝键'],['playPause','播放 / 暂停']];
function renderRemote(remote){setText(document.getElementById('digitStatus'),(remote?.keys||[]).some(item=>/^digit[0-9]$/.test(item.id))?'LCN 频道编号：按数字切换当前频道模式中的频道。':'LCN 数字键需要频道模式；当前 QA6 未提供频道模式，不用于首页角标或播放器选集。');const offered=new Map((remote?.keys||[]).map(item=>[item.id,item]));const items=[...['up','left','ok','right','down','back'].filter(id=>offered.has(id)).map(id=>offered.get(id)),...fixedExtras.map(([id,label])=>({id,label})),...Array.from({length:10},(_,i)=>({id:'digit'+i,label:String(i)})),...(remote?.keys||[]).filter(item=>!['up','left','ok','right','down','back',...fixedExtras.map(x=>x[0])].includes(item.id)&&!/^digit[0-9]$/.test(item.id))];
for(const item of items){let button=remoteButtons.get(item.id);if(!button){button=document.createElement('button');button.dataset.key=item.id;button.onclick=()=>{if(!button.disabled)sendRemote(item.id,state?.remote?.revision);};remoteButtons.set(item.id,button);let area='remoteExtras';if(['up','left','ok','right','down'].includes(item.id)){area='remoteDpad';button.style.gridArea=item.id;}else if(item.id==='back')area='remoteBack';else if(/^digit[0-9]$/.test(item.id))area='remoteDigits';document.getElementById(area).appendChild(button);}const capability=offered.get(item.id);const label=capability?(['menu','info','red','green','yellow','blue'].includes(item.id)?item.label+' · '+capability.label:capability.label):item.label+'（当前不可用）';if(button.textContent!==label)button.textContent=label;button.title=capability?'': '当前页面未提供此操作';button.disabled=!capability||offline||sending||composing||dirty;button.hidden=false;}
for(const [id,button] of remoteButtons){if(!items.some(item=>item.id===id))button.hidden=true;}}

function applyValue(s){const t=s.target;if(s.readTextAllowed&&typeof t?.text==='string'){box.value=t.text;const sel=t.selection;if(sel)box.setSelectionRange(Math.min(sel.baseOffset,sel.extentOffset),Math.max(sel.baseOffset,sel.extentOffset),sel.baseOffset>sel.extentOffset?'backward':'forward');}else box.value='';}
function update(s,ack=false){if(composing){deferred={s,ack};return;}const changed=key(state)!==key(s),revisionChanged=state?.target?.revision!==s.target?.revision;state=s;if(changed){dirty=false;selectionDirty=false;uncertain=false;applyValue(s);}else if(!ack&&revisionChanged&&(dirty||selectionDirty)){dirty=false;selectionDirty=false;uncertain=true;}else if(!dirty&&!selectionDirty&&s.readTextAllowed&&(revisionChanged||ack)){applyValue(s);}render();}
async function poll(){if(busy||composing)return;busy=true;try{const r=await request(base+'/state');if(!r.ok)throw Error();const s=await r.json();offline=false;update(s);}catch(e){offline=true;uncertain=true;}finally{busy=false;sending=false;render();}}
async function send(action){if(busy||composing||offline||!state?.target||(action==='confirm'&&uncertain))return false;busy=true;sending=true;render();const t=state.target,payload={requestId:client+'-'+(++serial),targetId:t.id,generation:state.generation,revision:t.revision,action,text:box.value};if(state.readTextAllowed&&(action==='input'||action==='selection'))payload.selection=selection();try{const r=await request(base+'/input',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(payload)});const s=await r.json();if(!r.ok){dirty=false;selectionDirty=false;uncertain=true;update(s);return false;}dirty=box.value!==payload.text;selectionDirty=!!payload.selection&&!sameSelection(selection(),payload.selection);if(action!=='confirm')uncertain=false;update(s,true);return true;}catch(e){dirty=false;selectionDirty=false;uncertain=true;offline=true;return false;}finally{busy=false;sending=false;render();}}
async function sendRemote(id,revision){if(busy||composing||offline||dirty||state?.remote?.revision!==revision)return false;busy=true;sending=true;render();const payload={requestId:client+'-'+(++serial),action:'remote',key:id,remoteRevision:revision,remoteSequence:(state.remoteSequence||0)+1};try{const r=await request(base+'/input',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(payload)});const s=await r.json();remoteMessage=r.ok?'':r.status===429?'按键过快，请稍后再按；不会自动重试':'场景已变化或操作未确认，请查看电视';update(s);return r.ok;}catch(e){offline=true;remoteMessage='操作结果未确认，请先查看电视；不会重发';return false;}finally{busy=false;sending=false;render();}}
box.addEventListener('compositionstart',()=>{composing=true;compositionTarget=key(state);compositionRevision=state?.target?.revision;render();});
box.addEventListener('compositionend',()=>{composing=false;const next=deferred;deferred=null;const conflict=next&&(key(next.s)!==compositionTarget||(!next.ack&&next.s.target?.revision!==compositionRevision));if(conflict){dirty=false;selectionDirty=false;update(next.s);applyValue(next.s);uncertain=true;discardComposition=true;render();return;}dirty=true;if(next)update(next.s,next.ack);if(compositionTarget!==key(state)){dirty=false;discardComposition=true;render();return;}send('input');});
box.addEventListener('input',()=>{if(composing)return;if(discardComposition){discardComposition=false;applyValue(state);dirty=false;render();return;}dirty=true;send('input');});
box.addEventListener('select',()=>{if(composing||!state?.readTextAllowed||sameSelection(selection(),state?.target?.selection))return;selectionDirty=true;if(!dirty)send('selection');});
clear.onclick=()=>{if(busy||composing)return;box.value='';dirty=true;send('clear');};
confirm.onclick=async()=>{if(busy||composing||uncertain||!state?.target)return;const target=key(state);if(dirty&&!(await send('input')))return;if(selectionDirty&&!(await send('selection')))return;if(!dirty&&!uncertain&&key(state)===target)await send('confirm');};
document.getElementById('keyboardMode').onclick=()=>{document.getElementById('keyboardPanel').hidden=false;document.getElementById('remotePanel').hidden=true;};document.getElementById('remoteMode').onclick=()=>{document.getElementById('keyboardPanel').hidden=true;document.getElementById('remotePanel').hidden=false;};
setInterval(()=>{if(dirty&&!busy&&!composing&&!uncertain)send('input');else if(selectionDirty&&!busy&&!composing&&!uncertain)send('selection');else poll();},800);poll();
</script></body></html>''';
