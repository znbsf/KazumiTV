/// Shared by the fallback and Android document-start parser. Keep syntax
/// compatible with WebView 66, bindings scoped and installation idempotent:
/// load callbacks can share a document and async replies can outlive a page.
String legacyVideoParserScript(
    {required int session, required bool iframeOnly}) {
  return _script
      .replaceAll('__SESSION__', '$session')
      .replaceAll('__IFRAME_ONLY__', '$iframeOnly');
}

String legacyVideoParserPollScript(int session) => '''
(function () {
  var state = window.__kazumiVideoParser;
  if (state && state.session === $session && state.active) state.scan();
})();
''';

const _script = r'''
(function () {
  if (window.location.href === 'about:blank') return;
  var session = __SESSION__;
  var old = window.__kazumiVideoParser;
  if (old && old.session === session && old.active) {
    old.scan();
    return;
  }
  if (old) old.dispose();
  var state = {
    session: session, active: true, frames: [], observers: [], hooks: [],
    pending: {}, sent: {}, listeners: [], iframeOnly: __IFRAME_ONLY__
  };
  window.__kazumiVideoParser = state;

  function isAd(src) {
    return /googleads|googlesyndication|adtrafficquality|doubleclick|prestrain(?:\.|%2e)html/i.test(src);
  }
  function absolute(src, win) {
    try {
      var anchor = win.document.createElement('a');
      anchor.href = src;
      return anchor.href;
    } catch (e) { return src; }
  }
  function emit(handler, src, win) {
    if (!state.active || !src || isAd(src)) return;
    src = absolute(src, win);
    if (!/^https?:\/\//i.test(src)) return;
    var key = handler + ':' + src;
    if (state.sent[key]) return;
    var bridge = window.flutter_inappwebview;
    if (!bridge || !bridge.callHandler) {
      state.pending[key] = [handler, src];
      return;
    }
    state.sent[key] = true;
    bridge.callHandler(handler, src, session);
  }
  function scanVideo(video, win) {
    // currentSrc includes URLs assigned through the DOM property, including
    // relative <source> URLs. A blob itself is never a playable network URL.
    var src = video.currentSrc || video.getAttribute('src');
    if (src && src.indexOf('blob:') !== 0) emit('VideoBridgeDebug', src, win);
    var sources = video.getElementsByTagName('source');
    for (var i = 0; i < sources.length; i++) {
      src = sources[i].getAttribute('src');
      if (src && src.indexOf('blob:') !== 0) emit('VideoBridgeDebug', src, win);
    }
  }
  function hookNetwork(win) {
    if (state.iframeOnly) return;
    if (win.Response && win.Response.prototype.text) {
      var proto = win.Response.prototype;
      var originalText = proto.text;
      var textHook = function () {
        var response = this;
        return originalText.call(response).then(function (text) {
          if (typeof text === 'string' && /^\s*#EXTM3U/.test(text)) {
            emit('VideoBridgeDebug', response.url, win);
          }
          return text;
        });
      };
      proto.text = textHook;
      state.hooks.push(function () {
        if (proto.text === textHook) proto.text = originalText;
      });
    }
    if (win.XMLHttpRequest && win.XMLHttpRequest.prototype.open) {
      var xhrProto = win.XMLHttpRequest.prototype;
      var originalOpen = xhrProto.open;
      var openHook = function () {
        var xhr = this;
        xhr.__kazumiRequestUrl = arguments[1];
        // Reusing an XHR must not accumulate one listener per open().
        if (xhr.__kazumiLoadHandlerState !== state) {
          if (xhr.__kazumiLoadHandler) {
            xhr.removeEventListener('load', xhr.__kazumiLoadHandler);
          }
          xhr.__kazumiLoadHandlerState = state;
          xhr.__kazumiLoadHandler = function () {
            try {
              if (/^\s*#EXTM3U/.test(xhr.responseText)) {
                emit('VideoBridgeDebug', xhr.responseURL || xhr.__kazumiRequestUrl, win);
              }
            } catch (e) {}
          };
          listen(xhr, 'load', xhr.__kazumiLoadHandler);
        }
        return originalOpen.apply(xhr, arguments);
      };
      xhrProto.open = openHook;
      state.hooks.push(function () {
        if (xhrProto.open === openHook) xhrProto.open = originalOpen;
      });
    }
  }
  function listen(target, event, callback, capture) {
    target.addEventListener(event, callback, !!capture);
    state.listeners.push(function () { target.removeEventListener(event, callback, !!capture); });
  }
  function visitFrame(frame, win) {
    // The iframe src can expose the same nested media URL as the existing
    // legacy parser. Read it without accessing a cross-origin document.
    emit('JSBridgeDebug', frame.getAttribute('src'), win);
    try {
      var child = frame.contentWindow;
      if (child && child.document) install(child);
    } catch (e) {} // The same-origin policy remains intact.
    if (state.frames.indexOf(frame) < 0) {
      state.frames.push(frame);
      listen(frame, 'load', function () {
        if (state.active) visitFrame(frame, win);
      });
    }
  }
  function scanDocument(win) {
    if (!state.active) return;
    try {
      var doc = win.document;
      var frames = doc.querySelectorAll('iframe');
      for (var i = 0; i < frames.length; i++) visitFrame(frames[i], win);
      if (!state.iframeOnly) {
        var videos = doc.querySelectorAll('video');
        for (var j = 0; j < videos.length; j++) scanVideo(videos[j], win);
      }
    } catch (e) {}
  }
  function install(win) {
    var doc = win.document;
    if (!doc || doc.__kazumiVideoParserState === state) return;
    doc.__kazumiVideoParserState = state;
    hookNetwork(win);
    var observer = new win.MutationObserver(function () { scanDocument(win); });
    state.observers.push(observer);
    // At document start even documentElement can be absent. Watching the
    // Document also catches elements created after DOMContentLoaded.
    observer.observe(doc, {
      childList: true, subtree: true, attributes: true, attributeFilter: ['src']
    });
    listen(doc, 'DOMContentLoaded', function () { scanDocument(win); });
    listen(doc, 'loadedmetadata', function (event) {
      if (!state.iframeOnly && event.target.nodeName === 'VIDEO') scanVideo(event.target, win);
    }, true);
    scanDocument(win);
  }
  state.scan = function () {
    var pending = state.pending;
    state.pending = {};
    for (var key in pending) {
      if (Object.prototype.hasOwnProperty.call(pending, key)) {
        emit(pending[key][0], pending[key][1], window);
      }
    }
    scanDocument(window);
  };
  state.dispose = function () {
    state.active = false;
    for (var i = 0; i < state.observers.length; i++) state.observers[i].disconnect();
    for (var j = 0; j < state.hooks.length; j++) state.hooks[j]();
    for (var k = 0; k < state.listeners.length; k++) state.listeners[k]();
    state.pending = {};
  };
  // Modern Android has no fallback polling timer. Flush sources discovered
  // before the bridge becomes available, even if the DOM never changes again.
  listen(window, 'flutterInAppWebViewPlatformReady', function () { state.scan(); });
  install(window);
})();
''';
