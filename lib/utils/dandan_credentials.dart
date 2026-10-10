// DanDanPlay API credentials for the client signature flow.
// Maintainers must inject DANDANAPI_APPID / DANDANAPI_KEY at build time.
// The credential-free TV candidate CI does not inject them; see
// docs/DANDANPLAY-ACCESS.md before treating a build as danmaku-ready.
const Map<String, String> dandanCredentials = {
  'id': String.fromEnvironment('DANDANAPI_APPID'),
  'value': String.fromEnvironment('DANDANAPI_KEY'),
};
