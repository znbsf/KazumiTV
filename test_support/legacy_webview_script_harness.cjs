'use strict';
// Runs the production scripts, rather than asserting their text. The small DOM
// model exercises hook and document lifetimes; it is not a browser or TV test.
const assert = require('node:assert/strict');
const vm = require('node:vm');
const fs = require('node:fs');
const scripts = JSON.parse(fs.readFileSync(0, 'utf8'));
const checks = [];

function eventTarget(value = {}) {
  value.listeners = {};
  value.addEventListener = function (name, listener) {
    (this.listeners[name] ||= []).push(listener);
  };
  value.removeEventListener = function (name, listener) {
    this.listeners[name] = (this.listeners[name] || []).filter(x => x !== listener);
  };
  value.fire = function (name, event = {}) {
    for (const listener of [...(this.listeners[name] || [])]) listener(event);
  };
  return value;
}
function realm(href = 'https://site.example/watch/1') {
  const calls = [], observers = [], frames = [], videos = [];
  function Response(url, body) { this.url = url; this.body = body; }
  Response.prototype.text = function () { return Promise.resolve(this.body); };
  function XHR() { eventTarget(this); }
  XHR.prototype.open = function (method, url) { this.opened = [method, url]; };
  function Observer(callback) { this.callback = callback; observers.push(this); }
  Observer.prototype.observe = function (target) { this.target = target; };
  Observer.prototype.disconnect = function () { this.disconnected = true; };
  const document = eventTarget({ documentElement: {} });
  document.createElement = function (name) {
    assert.equal(name, 'a');
    let result;
    return { set href(value) { result = new URL(value, href).href; }, get href() { return result; } };
  };
  document.querySelectorAll = name => name === 'iframe' ? frames : videos;
  const window = eventTarget({ document, Response, XMLHttpRequest: XHR, MutationObserver: Observer,
    location: { href }, flutter_inappwebview: { callHandler: (...args) => calls.push(args) } });
  const context = vm.createContext({ window, document });
  return { window, document, calls, observers, frames, videos,
    run: script => vm.runInContext(script, context),
    mutations: () => observers.filter(x => !x.disconnected).forEach(x => x.callback([])) };
}
function frame(src, child, inaccessible = false) {
  const result = eventTarget({ nodeName: 'IFRAME', getAttribute: key => key === 'src' ? src : null });
  Object.defineProperty(result, 'contentWindow', { get() {
    if (inaccessible) throw Error('SecurityError: cross-origin access denied');
    return child?.window;
  } });
  return result;
}
function video(src, sources = []) {
  return { nodeName: 'VIDEO', currentSrc: src,
    getAttribute: key => key === 'src' ? src : null,
    getElementsByTagName: () => sources.map(item => ({ getAttribute: () => item })) };
}
async function check(name, action) { await action(); checks.push({ name, passed: true }); }

(async () => {
  await check('repeated installation is idempotent and fetch text still resolves', async () => {
    const page = realm();
    page.run(scripts.normal1);
    const hook = page.window.Response.prototype.text;
    page.run(scripts.normal1);
    assert.equal(page.window.Response.prototype.text, hook);
    assert.equal(page.observers.length, 1);
    const response = new page.window.Response('https://media.example/live/index.m3u8', '#EXTM3U\n');
    assert.equal(await response.text(), '#EXTM3U\n');
    await response.text();
    assert.deepEqual(page.calls, [['VideoBridgeDebug', response.url, 1]]);
  });
  await check('public iframe media query survives cross-origin and failed site JS', async () => {
    const page = realm();
    const source = 'https://site.example/artplayer/index.html?url=https://media.example/index.m3u8';
    page.frames.push(frame(source, null, true));
    // A source player cannot parse optional chaining on Chromium 66. Its
    // failure does not stop the app-owned script reading the iframe src.
    assert.throws(() => page.run('throw new SyntaxError("Unexpected token .")'));
    page.run(scripts.normal1);
    page.run(scripts.normal1);
    assert.deepEqual(page.calls, [['JSBridgeDebug', source, 1]]);
  });
  await check('same-origin iframe response hooks and dynamic nested frames work', async () => {
    const page = realm(), child = realm('https://site.example/player/frame');
    page.run(scripts.normal1);
    const added = frame('/player/frame', child);
    page.frames.push(added);
    page.mutations();
    assert.equal(await new child.window.Response('https://media.example/nested.m3u8', '#EXTM3U').text(), '#EXTM3U');
    assert(page.calls.some(args => args[0] === 'VideoBridgeDebug' && args[1] === 'https://media.example/nested.m3u8'));
    assert.equal(added.listeners.load.length, 1);
    page.mutations();
    assert.equal(added.listeners.load.length, 1);
    assert.equal(child.observers.length, 1);
  });
  await check('XHR reuse has one listener and reports current response URL', async () => {
    const page = realm();
    page.run(scripts.normal1);
    const xhr = new page.window.XMLHttpRequest();
    xhr.open('GET', '/one.m3u8');
    xhr.open('GET', '/two.m3u8');
    assert.equal(xhr.listeners.load.length, 1);
    xhr.responseText = '#EXTM3U';
    xhr.responseURL = 'https://media.example/redirected.m3u8';
    xhr.fire('load');
    assert.deepEqual(page.calls, [['VideoBridgeDebug', xhr.responseURL, 1]]);
  });
  await check('new session disposes old hooks, observers and queued async replies', async () => {
    const page = realm();
    let finish;
    page.window.Response.prototype.text = () => new Promise(resolve => { finish = resolve; });
    page.run(scripts.normal1);
    const pending = new page.window.Response('https://media.example/old.m3u8', '').text();
    const old = page.window.__kazumiVideoParser;
    page.run(scripts.normal2);
    assert.equal(old.active, false);
    assert.equal(page.observers[0].disconnected, true);
    assert.equal(page.document.listeners.loadedmetadata.length, 1);
    finish('#EXTM3U');
    await pending;
    assert.deepEqual(page.calls, []);
    const xhr = new page.window.XMLHttpRequest();
    xhr.open('GET', 'https://media.example/new.m3u8');
    xhr.responseText = '#EXTM3U'; xhr.fire('load');
    assert.deepEqual(page.calls, [['VideoBridgeDebug', 'https://media.example/new.m3u8', 2]]);
  });
  await check('currentSrc, relative source, blob and ad filtering are distinct', async () => {
    const page = realm();
    page.videos.push(video('blob:https://site.example/id', ['/media/legitimate.mp4']));
    page.videos.push(video('https://googleads.example/ad.mp4'));
    page.videos.push(video('https://media.example/current.mp4'));
    page.run(scripts.normal1);
    assert.deepEqual(page.calls, [
      ['VideoBridgeDebug', 'https://site.example/media/legitimate.mp4', 1],
      ['VideoBridgeDebug', 'https://media.example/current.mp4', 1]
    ]);
  });
  await check('bridge-not-ready queues deduplicate and retry on scan', async () => {
    const page = realm();
    const bridge = page.window.flutter_inappwebview;
    page.window.flutter_inappwebview = null;
    page.videos.push(video('/media/a.mp4'));
    page.run(scripts.normal1);
    page.run(scripts.normal1);
    assert.equal(Object.keys(page.window.__kazumiVideoParser.pending).length, 1);
    page.window.flutter_inappwebview = bridge;
    page.run(scripts.poll1);
    assert.deepEqual(page.calls, [['VideoBridgeDebug', 'https://site.example/media/a.mp4', 1]]);
  });
  await check('blank pages stay untouched and iframe-only mode preserves rule semantics', async () => {
    const blank = realm('about:blank');
    blank.run(scripts.normal1);
    assert.equal(blank.window.__kazumiVideoParser, undefined);
    const page = realm();
    const original = page.window.Response.prototype.text;
    page.videos.push(video('https://media.example/ignored.mp4'));
    page.frames.push(frame('https://site.example/player?url=https://media.example/a.mp4', null, true));
    page.run(scripts.iframe1);
    assert.equal(page.window.Response.prototype.text, original);
    assert.deepEqual(page.calls, [['JSBridgeDebug', 'https://site.example/player?url=https://media.example/a.mp4', 1]]);
  });
  await check('document-start observes late elements before a document root exists', async () => {
    const page = realm();
    page.document.documentElement = null;
    page.run(scripts.normal1);
    assert.equal(page.observers[0].target, page.document);
    page.document.documentElement = {};
    page.document.fire('DOMContentLoaded');
    page.videos.push(video('/media/late.mp4'));
    page.mutations();
    assert.deepEqual(page.calls, [['VideoBridgeDebug', 'https://site.example/media/late.mp4', 1]]);
  });
  await check('bridge-ready flushes early results once without a polling timer', async () => {
    const page = realm(), bridge = page.window.flutter_inappwebview;
    page.window.flutter_inappwebview = null;
    page.videos.push(video('/media/early.mp4'));
    page.run(scripts.normal1);
    page.window.flutter_inappwebview = bridge;
    page.window.fire('flutterInAppWebViewPlatformReady');
    page.window.fire('flutterInAppWebViewPlatformReady');
    assert.deepEqual(page.calls, [['VideoBridgeDebug', 'https://site.example/media/early.mp4', 1]]);
    page.window.__kazumiVideoParser.dispose();
    assert.equal(page.window.listeners.flutterInAppWebViewPlatformReady.length, 0);
  });
  process.stdout.write(JSON.stringify({ checks }));
})().catch(error => { process.stderr.write(error.stack); process.exitCode = 1; });
