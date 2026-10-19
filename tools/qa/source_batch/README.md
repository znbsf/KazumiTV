# 电脑批量解析 / GeckoView QA

仅实验包 `com.znbsf.kazumi.fluttertv.parserqa`，debug/x86_64/API26+。运行器硬拒绝物理设备；不安装 APK、不改变正式包。调用者先检查 APK 包名，再明确安装到专用 emulator。Gecko 只解析地址，播放仍使用项目 media-kit 的真实首帧回调、静音软件输出。生产构建不启用 `kazumiParserQa` 时不包含依赖、Activity、扩展。

## 构建及运行

1. 使用项目既有 Flutter3.47.3 工具链和已解析依赖，运行 `build.ps1`，传入 `FlutterRoot/PubCache/GradleHome/JavaHome/Output/Python`。它生成与生产共用的解析脚本、构建实验 APK 并保存源码内容哈希/基线 SHA/APK 哈希。缺少 Android 插件元数据时按构建 runbook 的 Android-only 流程准备；不更改 Windows 开发者模式。
2. 新建专用 API36 Google TV x86_64 AVD；以 `-no-window -no-audio -no-snapshot -gpu swiftshader -cores 2 -memory 2048` 后台启动，选择未占用端口。不得复用/清除他人 AVD。
3. 用 Android SDK `aapt dump badging` 核实 APK 包名及 x86_64，再使用明确 emulator serial 安装；运行器会核对已安装 APK 与传入文件的 SHA256。
4. 自行生成 320x180 H264/MP4 测试图（例如 ffmpeg testsrc2，8秒，无音频）。运行：

```text
python run.py --adb <adb.exe> --serial emulator-5580 --apk <parserqa.apk> --manifest fixtures.json --fixture-media <fixture.mp4> --output <new-fixture-results> --repeats 1
python run.py --adb <adb.exe> --serial emulator-5580 --apk <parserqa.apk> --manifest live.json --output <new-live-results> --repeats 2
```

单例70秒；每轮最多24例/30分钟；host timeout 或清理未确认停止该轮。在输出目录创建 `STOP` 可完成当前例后停止。`attempts.jsonl` 记录开始、`results.jsonl` 记录完成；未知结果拒绝自动重试。相同输出目录只允许完全相同 APK/清单/模拟器/运行器身份，已有 ledger 行不重跑。变更样本/产物用新的目录，保留失败结果。结束运行器关闭自建服务器/采样线程并 force-stop 实验包；宿主负责关闭自己启动的 emulator 并核实退出。

## 清单与结果契约 v1

- 清单 `cases[]`：`id/group` 必填；真实源使用 `rule_file/keyword/names/road/episode`，后两项零基索引。精确匹配唯一作品，不自动采用搜索第一项。规则 JSON 内联后计算摘要；目前 `overlay=none`，不修改规则/覆盖模型。
- 固定清单中的同一例分别跑 webview/gecko，奇偶样本及重复轮交换顺序；每次 force-stop 后冷进程启动。浏览器缓存策略不同但都不复用网页会话；OS/DNS 缓存仍可能热。固定同一 UA，此结果不是各内核默认 UA 的比较。
- `identity.json` 关联 APK/清单哈希、Android fingerprint、serial、UA；旁边保留 `artifact.json/source-digests.json`。`results.jsonl` 是可恢复账本；`summary.json/report.html` 为派生报告，不能代替原始行。
- 每行记录 engine/environment（实际 provider/version/SDK/ABI）、rule version/content hash/fingerprint/overlay、案例/匹配作品/线路/集标签/剧集页摘要、启用能力与结果。内部地址可写本地输入；对外报告只保留媒体 host 和摘要，不公开签名 URL/原始日志。
- 分阶段 `search/chapters/resolve/media_open/first_frame/total` 毫秒；`progress_ms` 为首帧后2秒进度。`media_open` 是播放器 open 完成时间，不是独立 HTTP TTFB。未到达的阶段缺失，不能计失败。无匹配/歧义/缺集/验证码/阶段超时/错误分别保留。resolved 不等于可播放；首帧不等于长稳/音画同步。
- 内存每约1秒用 `dumpsys meminfo` 采样 PSS：App 命名进程 + 专用模拟器本例新增的命名 WebView sandbox 进程。记录 PID/进程名和样本；缺失用 null，不用0；这是采样峰值，未包含共享系统服务，也不是严格完整浏览器归因。不得拿单主进程冒充全内核内存。
- 报告先分 fixture/live/negative fixture。成功率同时保留全部尝试数、解析成功数、真实首帧数；速度中位数只针对成功阶段，失败/未执行分母单列。跨引擎需核对 `episode_page_sha256` 相同才称同集配对。小样本不外推全站成功率。

## 已知实验限制

Gecko158实测要求 compileSdk37/AGP9.1+，本原型固定146.0.20251217121356（与现有工具链兼容的较旧稳定版），不是最新安全版本或生产推荐。系统 WebView 记录运行时实际版本。Gecko通过内置 WebExtension 在 MAIN world 注入同一解析脚本，覆盖所有 http(s) 子框架，与 Android document-start 注入范围一致（插件 forMainFrameOnly 仅对 iOS/macOS 生效）。内容桥接是只读候选输入，并由当前 session/generation 和生产 URL 校验隔离。尚不支持 `useLegacyParser=true` 的 iframe-only 模式，显式失败，不悄悄改变规则。

固定UA取自 App 的 `userAgentsList` 第一项。初始手机UA实验发现7sefun跳转App下载页，已保留并排除出代表App的比较。诊断补充后必须重测跨域 iframe，用它区分桥接覆盖缺口和真实内核兼容失败。扩展脚本变化时更新 manifest version，避免复用旧内置扩展注册。

两个内核都关闭网络图片；Gecko使用内置扩展阻止 image 请求。APK 为 Flutter debug 包（原生依赖可能包含其他 ABI），本轮只执行 x86_64；不可把包大小或 debug PSS 当生产开销。

现代模拟器不能证明 Android9/WebView66/ARMv7 电视兼容；本轮不操作电视，不绕过站点挑战。搜索/集表失败通常先排查规则/网络；已确认同一剧集一内核失败另一成功，才是运行时差异线索。HTTP请求响应的逐包对照、热会话/长时间取消压力、最新Gecko及旧Android矩阵仍需后续独立验证。

规则覆盖会话负责声明式契约，本工具只消费既有 Plugin 规则，不包含第二套覆盖实现；不把 HHJX 兼容补救偷偷转成任意规则脚本。

集成适配入口：清单可以直接传入 `rule: <effective plain JSON>`，无需 `rule_file`。规则候选/集成树负责调用 `plugin.toJson(includeLocalMetadata: false)`；当前分支不导入尚未合入的 RuleOverlay。可附 `rule_provenance: {overlay, base_sha256, effective_sha256, upstream_commit}`，运行器原样携带为调用者声明，同时独立记录输入 JSON SHA256 与运行时 ruleFingerprint；三种摘要算法不应混用。未知上游 commit 必须 null。基础/有效对照各自作为不同案例，禁止修改真实规则列表以构造对照。

官方参考：[GeckoView WebExtensions](https://firefox-source-docs.mozilla.org/mobile/android/geckoview/consumer/web-extensions.html)、[MAIN world 支持](https://blog.mozilla.org/addons/2024/07/10/manifest-v3-updates-landed-in-firefox-128/)。
