# 流式响应整次请求期限 · 2026-09-22

仓库使用OkHttp 4.12.0和Media3 1.8.0。OkHttp的整次请求期限包含响应体读取；Media3将同一次请求的响应流用于持续读取。因此，原AppHttp的30秒期限会取消尚未读完的媒体响应。缓冲或后续Range重连可能遮蔽此问题，不能把它直接等同于画面第30秒停止。

版本对应的一手依据：

- [OkHttp 4.12.0 OkHttpClient](https://raw.githubusercontent.com/square/okhttp/parent-4.12.0/okhttp/src/main/kotlin/okhttp3/OkHttpClient.kt)：`callTimeout`文档说明范围包括响应体读取，0表示无整次期限；`readTimeout`仍约束单次读取。
- [OkHttp 4.12.0 RealCall](https://raw.githubusercontent.com/square/okhttp/parent-4.12.0/okhttp/src/main/kotlin/okhttp3/internal/connection/RealCall.kt)：`messageDone`/`callDone`在响应流结束后退出期限。
- [Media3 1.8.0 OkHttpDataSource](https://raw.githubusercontent.com/androidx/media/1.8.0/libraries/datasource_okhttp/src/main/java/androidx/media3/datasource/okhttp/OkHttpDataSource.java)：`open`持有响应的`byteStream`，后续`read`持续读取，没有移除OkHttp整次请求期限。

修复仅增加`AppHttp.streamingClient`，派生原客户端并设`callTimeout=0`。NativePlayer和OfflineDownloads使用它；原连接12秒、读取15秒、连接池和播放Cookie策略保持，下载仍保留其禁用Cookie和跨域敏感头过滤。文本请求30秒、媒体probe每次5秒不变。

受控入口为`StreamingTimeoutRegression.run()`：三个并行本地请求直接使用生产OkHttpDataSource。基线保留30秒期限；流式客户端读取每秒一字节的36字节响应至完整EOF，经过约35秒；另一路以250毫秒读取期限验证停顿仍失败。断言精确内容、超时异常类型、完整字节数和每路单请求，避免重连掩盖问题。不读取用户媒体，不进行真实下载或整集测试。

设备回归已通过，均使用本地候选 APK SHA256 `ab83f4b46af8852848d7ebc1bd61de0caab9c86c7871c695fa5d0148bf57a65f`：

| 设备 | 基线取消 | 流式完整读取 | 结果 |
| --- | --- | --- | --- |
| MiTV / WebView 66 | 30016 ms | 35125 ms、36 字节 | PASS |
| Google TV 模拟器 / WebView 143 | 30012 ms | 35177 ms、36 字节 | PASS |

两端均确认单次请求、完整内容和读取超时仍有效。本地记录为 `artifacts/recovery-20260922/streaming-tv.txt` 与 `streaming-modern.txt`；构建、194 项单元测试和 release lint 通过。这是传输层受控回归，不能代替真实来源播放、断网恢复或完整迁移验收。公开 Preview 4 尚不包含此改动。
