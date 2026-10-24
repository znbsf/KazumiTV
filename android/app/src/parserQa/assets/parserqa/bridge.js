// Page events are untrusted parser candidates, never privileged commands.
window.addEventListener('message', event => {
  if (event.source !== window || event.origin !== location.origin) return;
  const value = event.data;
  if (!value || value.type !== 'kazumi-parser-qa' ||
      !['JSBridgeDebug', 'VideoBridgeDebug'].includes(value.handler) ||
      typeof value.url !== 'string' || value.url.length > 16384) return;
  browser.runtime.sendNativeMessage('kazumi_parser', {
    handler: value.handler, url: value.url
  }).catch(() => {});
});
const snapshot = () => browser.runtime.sendNativeMessage('kazumi_parser', {
  handler: 'Snapshot', ready: document.readyState,
  frames: document.querySelectorAll('iframe').length,
  videos: document.querySelectorAll('video').length
}).catch(() => {});
window.addEventListener('load', snapshot, {once: true});
setTimeout(snapshot, 5000);
