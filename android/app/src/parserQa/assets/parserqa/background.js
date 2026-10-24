// Match the production Android parser's blockNetworkImage policy for A/B.
browser.webRequest.onBeforeRequest.addListener(
  () => ({cancel: true}),
  {urls: ['http://*/*', 'https://*/*'], types: ['image']},
  ['blocking']
);
