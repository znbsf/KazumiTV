# 播放架构参考：源码初审

2026-09-16。用户要求参考 GitHub 上架构相似的开源项目。以下是固定提交的源码初审，不是项目全量审计，也不代表已经移植或在电视验证。

优先级保持：Kazumi 上游功能等价 → Android TV / WebView 能力差异 → 其他项目补充方案。沿用现有主页风格，不因参考项目重启架构或替换规则生态。

## WebView 平台差异与当前缺口

2026-09-16 对照本地上游快照 `1b395a50`（不表示已联网确认最新上游）：

- Kazumi 用统一 VideoWebviewController 接口隔离实现：Windows、Linux、Apple 分支；Android 检测 DOCUMENT_START_SCRIPT 能力，支持时走现代实现，不支持时走兼容实现。验证码也有独立控制器和平台工厂。
- Android 系统版本不能单独代表 WebView 能力，需检查实际 WebView 提供程序、版本与功能支持。网页开始前注入、子框架、请求拦截、Cookie、代理和生命周期都是对照维度，不能假设各平台行为一致。
- 当前原生版（0.3.1-preview.1）使用兼容脚本、请求拦截、页面数据解析及少量站点接口适配；尚未建立上游那样的能力检测与现代/兼容双分支。该项是下一轮播放重点，不标作已完成。
- 区分我们的注入脚本不兼容和站点自身现代 JavaScript 无法运行：前者可通过兼容语法改善，后者不能靠修改注入脚本或伪装 UA 解决。只有通用能力仍不足且证据明确时才加站点专用路径。
- WebView 负责网页执行、验证和媒体地址获取；原版内置播放通常交给 media-kit/libmpv，当前原生版交给 Media3。网页解析失败与媒体请求/解码失败必须分别诊断。

来源：[上游控制器](https://github.com/Predidit/Kazumi/blob/1b395a50/lib/webview/video/video_webview_controller.dart)、[上游能力检测](https://github.com/Predidit/Kazumi/blob/1b395a50/lib/services/platform/webview_feature_service.dart)、[Android WebView 功能检测](https://developer.android.com/reference/androidx/webkit/WebViewFeature)。

## 已核对的实现

- `open-ani/animeko`：`616eaae77a2faa2d482d26574f15316607770a0e`，仓库许可标识 `AGPL-3.0`。
- `easybangumiorg/EasyBangumi`：`fed45da5fd0a508ec313fdb3f9054c687e724545`，仓库许可标识 `GPL-3.0`。
- `recloudstream/cloudstream`：`81dbdf4b4483ee72566f108ac9cde998a79e519e`，仓库许可标识 `GPL-3.0`。

### Animeko：平台实现与验证会话

[WebViewVideoExtractor.android.kt](https://github.com/open-ani/animeko/blob/616eaae77a2faa2d482d26574f15316607770a0e/app/shared/app-data/src/androidMain/kotlin/domain/media/resolver/WebViewVideoExtractor.android.kt)、[WebViewVideoExtractor.desktop.kt](https://github.com/open-ani/animeko/blob/616eaae77a2faa2d482d26574f15316607770a0e/app/shared/app-data/src/desktopMain/kotlin/domain/media/resolver/WebViewVideoExtractor.desktop.kt)、[WebSessionManager.kt](https://github.com/open-ani/animeko/blob/616eaae77a2faa2d482d26574f15316607770a0e/app/shared/app-data/src/commonMain/kotlin/domain/mediasource/web/captcha/WebSessionManager.kt)

- Android 工厂选择 AndroidWebViewVideoExtractor，桌面选择 CefVideoExtractor；相同接口并不意味着内核与代理能力一致，Android 工厂明确标注不支持该代理参数。
- WebSessionManager 集中管理页面结果判定、按来源会话、Cookie/UA 同步、超时、取消和浏览器创建并发限制。借鉴方向：验证成功应以恢复后的业务页面为准，不只看挑战元素消失。
- 我们已有验证串行、Cookie/原请求恢复；下一步评估按来源隔离会话、失效回退与统一错误状态，避免重复建设。
- 本轮只参考结构。该仓库标识 AGPL-3.0；直接引入代码或模型之前须逐文件核对许可及发布影响，不默认按当前 GPL 项目原样复制。

### EasyBangumi：WebView 生命周期与异常退出兼容

[WebViewManager.kt](https://github.com/easybangumiorg/EasyBangumi/blob/fed45da5fd0a508ec313fdb3f9054c687e724545/app/src/main/java/com/heyanle/easybangumi4/utils/WebViewManager.kt)、[WebViewCompatibilityModeGuard.kt](https://github.com/easybangumiorg/EasyBangumi/blob/fed45da5fd0a508ec313fdb3f9054c687e724545/app/src/main/java/com/heyanle/easybangumi4/utils/WebViewCompatibilityModeGuard.kt)

- WebViewManager 在主线程创建浏览器，维护一个核心空闲实例，多余回收实例销毁。注意这不是全局最多一个活动 WebView，不能误读成并发上限。
- 兼容模式守卫在风险操作前留下持久标记，正常结束清除；下次启动发现残留可触发兼容模式，覆盖原生崩溃无法执行 finally 的情况。
- 借鉴方向：统一解析/验证的生命周期和资源预算；补渲染进程退出、初始化失败、重启后的降级。残留标记也可能来自强杀/掉电，不能直接当作已证实 WebView 崩溃；我们应结合证据并提供可恢复策略。

### Cloudstream：解析结果携带完整播放上下文

[WebViewResolver.android.kt](https://github.com/recloudstream/cloudstream/blob/81dbdf4b4483ee72566f108ac9cde998a79e519e/library/src/androidMain/kotlin/com/lagradost/cloudstream3/network/WebViewResolver.android.kt)、[ExtractorApi.kt](https://github.com/recloudstream/cloudstream/blob/81dbdf4b4483ee72566f108ac9cde998a79e519e/library/src/commonMain/kotlin/com/lagradost/cloudstream3/utils/ExtractorApi.kt)、[WebViewResolver.jvm.kt](https://github.com/recloudstream/cloudstream/blob/81dbdf4b4483ee72566f108ac9cde998a79e519e/library/src/jvmMain/kotlin/com/lagradost/cloudstream3/network/WebViewResolver.jvm.kt)

- Android WebViewResolver 使用请求匹配、回调、超时和销毁；ExtractorLink 明确携带 Referer、headers、媒体类型等，而不只交付 URL。
- 借鉴方向：审核我们的解析结果→媒体探测→Media3→失效重解析全链路，确保请求上下文不丢失，区分解析、HTTP 和解码错误。
- 不照搬：当前所读 Android 实现包含 SSL 错误直接 proceed；我们不引入该行为。JVM 的核心解析重载仍为 TODO，不能因为存在跨平台接口就认定每个平台已可用。

## 下一轮实施顺序与验收

1. 对齐 Kazumi 的能力检测与现代/兼容解析分支：新内核文档开始注入、旧内核拦截与兼容检测。两类设备跑相同用例；功能探测失败也能退出或降级。
2. 统一播放请求与来源验证上下文：重定向、Cookie/UA/Referer、POST、取消、错误阶段、重新解析。已有能力先审计差异再补代码。
3. 生命周期与故障恢复：超时/取消/退出释放，渲染进程异常与重启恢复，限制低内存设备同时运行的浏览器数量。
4. 真机完整观看：真实源搜索验证、选集入播、持续播放、快进暂停、换线换集、失败重试、返回续播，以及网络/待机恢复。受控测试补异常覆盖，不能代替真实来源。

本站点专项兼容仍保留，但不作为逐个源硬编码的默认路线。每次实际移植需记录原提交、文件、许可、改动理由和对应验收证据。
