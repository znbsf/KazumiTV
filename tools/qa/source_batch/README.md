# 电脑批量 App 服务路径 / GeckoView QA

仅实验包 `com.znbsf.kazumi.fluttertv.parserqa`，debug/x86_64/API26+。运行器硬拒绝物理设备；不安装 APK、不改变正式包。调用者先检查 APK 包名，再明确安装到专用 emulator。Gecko 只解析地址，播放仍使用项目 media-kit 的真实首帧回调、静音软件输出。生产构建不启用 `kazumiParserQa` 时不包含依赖、Activity、扩展。

默认 `--engines app`：搜索/集表调用现有Plugin；解析调用生产 `VideoWebviewControllerFactory`，由真实DOCUMENT_START_SCRIPT能力选择现代/legacy实现（包含WebView66的兼容准入）；媒体头使用 `Plugin.buildHttpHeaders`，确认地址缓存复用 `ResolvedSourceCache`；播放直接复用 `PlayerPlaybackController`，包含缓冲策略、广告过滤、代理、真实SDK/模拟器输出选择和错误/释放处理。QA Activity继承生产MainActivity以复用原生通道，只在debug实验身份下启用TV模式测试钩子。首帧仍须实际native回调，不能只看尺寸。

这仍是服务/播放控制器批测；它按清单选择作品/线路/剧集，未经过首页、详情、遥控焦点、切集界面、历史/弹幕等完整UI。不得将结果标记为全App端到端通过。UI遥控回归应另用正式App入口的独立测试包及真实DPAD动作。

`--engines webview,gecko` 保留上一轮受控内核比较：固定浏览器/媒体UA、现代WebView控制器、8MiB缓冲和软件输出。其结果不得混入 `app` profile。app模式进程冷启，缓存代码被调用但不会凭此证明缓存失败回退或历史续播已测。

## 构建及运行

构建前必须存在 `android/app/src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java`。Windows离线 `pub get` 在软链阶段失败后，即使已有package_config等依赖元数据，也不代表Android插件注册已生成；缺失会造成APK可以构建、启动却报MissingPluginException（例如package_info）。须先由固定Flutter工具的 **Android-only injectPlugins准备流程** 生成注册文件（这是Flutter工具内部API，不是CLI子命令），然后再运行本脚本。脚本在解析脚本生成、创建输出目录及构建之前检查；缺失立即失败，不自动生成、不复制该Java文件入库，也不修改系统设置。此生成文件保持忽略，但其内容哈希明确纳入source-digests.json及构建前后比较。

1. 使用项目既有 Flutter3.47.3 工具链和已解析依赖，运行 `build.ps1`，传入 `FlutterRoot/PubCache/GradleHome/JavaHome/Output/Python`。它生成与生产共用的解析脚本、构建实验 APK 并保存源码内容哈希/基线 SHA/APK 哈希。缺少 Android 插件元数据时按构建 runbook 的 Android-only 流程准备；不更改 Windows 开发者模式。
2. 新建专用 API36 Google TV x86_64 AVD；以 `-no-window -no-audio -no-snapshot -gpu swiftshader -cores 2 -memory 2048` 后台启动，选择未占用端口。不得复用/清除他人 AVD。
3. 用 Android SDK `aapt dump badging` 核实 APK 包名及 x86_64，再使用明确 emulator serial 安装；运行器会核对已安装 APK 与传入文件的 SHA256。
4. 自行生成 320x180 H264/MP4 测试图（例如 ffmpeg testsrc2，8秒，无音频）。运行：

```text
python run.py --adb <adb.exe> --serial emulator-5582 --apk <parserqa.apk> --manifest live.json --engines app --expect-sdk 28 --expect-webview 66.0.3359.158 --output <new-app-results>
python run.py --adb <adb.exe> --serial emulator-5580 --apk <parserqa.apk> --manifest live.json --engines webview,gecko --output <new-controlled-results> --repeats 2
```

单例70秒；每轮最多24例/30分钟；host timeout 或清理未确认停止该轮。在输出目录创建 `STOP` 可完成当前例后停止。`attempts.jsonl` 记录开始、`results.jsonl` 记录完成；未知结果拒绝自动重试。相同输出目录只允许完全相同 APK/清单/模拟器/运行器身份，已有 ledger 行不重跑。变更样本/产物用新的目录，保留失败结果。结束运行器关闭自建服务器/采样线程并 force-stop 实验包；宿主负责关闭自己启动的 emulator 并核实退出。

## 清单与结果契约 v1

- 清单 `cases[]`：`id/group` 必填；真实源使用 `rule_file/keyword/names/road/episode`，后两项零基索引。精确匹配唯一作品，不自动采用搜索第一项。规则 JSON 内联后计算摘要；目前 `overlay=none`，不修改规则/覆盖模型。
- 固定清单中的同一例分别跑 webview/gecko，奇偶样本及重复轮交换顺序；每次 force-stop 后冷进程启动。浏览器缓存策略不同但都不复用网页会话；OS/DNS 缓存仍可能热。固定同一 UA，此结果不是各内核默认 UA 的比较。
- `app` profile 保留App默认UA行为，记录actual_controller、能力准入、是否命中确认缓存及实际播放配置；不强制桌面UA或伪造WebView版本。`--expect-sdk/--expect-webview`先核对系统选中provider，每例再核对App实际报告，错配标为environment_invalid并停止。
- `identity.json` 关联 APK/清单哈希、Android fingerprint、serial、UA；旁边保留 `artifact.json/source-digests.json`。`results.jsonl` 是可恢复账本；`summary.json/report.html` 为派生报告，不能代替原始行。
- 每行记录 engine/environment（实际 provider/version/SDK/ABI）、rule version/content hash/fingerprint/overlay、案例/匹配作品/线路/集标签/剧集页摘要、启用能力与结果。内部地址可写本地输入；对外报告只保留媒体 host 和摘要，不公开签名 URL/原始日志。
- 分阶段 `search/chapters/resolve/media_open/first_frame/total` 毫秒；`progress_ms` 为首帧后2秒进度。`media_open` 是播放器 open 完成时间，不是独立 HTTP TTFB。未到达的阶段缺失，不能计失败。无匹配/歧义/缺集/验证码/阶段超时/错误分别保留。resolved 不等于可播放；首帧不等于长稳/音画同步。
- 内存每约1秒用 `dumpsys meminfo` 采样 PSS：App 命名进程 + 专用模拟器本例新增的命名 WebView sandbox 进程。记录 PID/进程名和样本；缺失用 null，不用0；这是采样峰值，未包含共享系统服务，也不是严格完整浏览器归因。不得拿单主进程冒充全内核内存。
- 报告先分 fixture/live/negative fixture。成功率同时保留全部尝试数、解析成功数、真实首帧数；速度中位数只针对成功阶段，失败/未执行分母单列。跨引擎需核对 `episode_page_sha256` 相同才称同集配对。小样本不外推全站成功率。

### 报告/清理契约 v2

- 环境错配的 `stage=environment_invalid` 优先于残留error_type；原stage保留在observed_stage。每组 `attempted` 仍是有终态记录数，另报 `invalid/infrastructure/eligible_results`；无效环境不进入解析/首帧/耗时/PSS统计，不把它归为解析失败。原始results行不改写。
- 新批次在identity保存 `planned_attempts`，另存无URL的 `plan.json`（key、案例、engine、group、repeat）。开始日志和结果账本分别追加。报告重建输出 `report_schema=2`，同时报告planned、started、completed、unknown、unattempted及case_states；completed表示持久终态记录，不表示产品通过。
- `unknown` 是有开始、无终态；`unattempted` 必须有可信计划和完整开始日志才计算。旧identity没计划时可使用原summary已保存的planned，但不能从结果数推断总计划。缺计划/开始日志或日志截断时，相应总数为JSON null、界面显示unknown。`known_unknown` 只是可识别的下界；`remaining_without_result` 包含unknown与unattempted，不冒充后者。旧的未保存案例清单不能追补案例名称。
- `report.py <folder>` 只重建summary.json、comparison.md、report.html，不改identity、plan、attempts或results。CLI标准输出从旧版摘要数组改为v2完整对象，其 `summary` 字段保留原每组统计数组。消费方须按report_schema识别；跨运行器版本继续要求新的输出目录。
- 单例和整批清理逐步独立尝试：停止QA、读取进程表、采样线程退出、fixture shutdown/close、每个已申请反向端口移除、报告写入。force-stop成功不能证明退出；named QA进程（单例另含基线之外可识别WebView renderer）必须在有效进程清单中消失，否则host_cleanup=unconfirmed。它不证明未命名共享系统服务已退出。
- App的cleanup与host_cleanup分别保留。任何单例清理未确认都会停止后续案例；只有清理失败时以BatchCleanupError非零退出；已有主异常或用户中断时重新抛出原异常，清理错误不能覆盖它。`.host-error.json`、run-status.json、cleanup.json保留异常类型/超时和各步失败，不记录可能含签名地址的异常命令。因原始异常未拿到App终态的案例仍是unknown，不伪造产品失败行。cleanup.json是最终清理收据；报告可再次离线重建。

## 已知实验限制

Gecko158实测要求 compileSdk37/AGP9.1+，本原型固定146.0.20251217121356（与现有工具链兼容的较旧稳定版），不是最新安全版本或生产推荐。系统 WebView 记录运行时实际版本。Gecko通过内置 WebExtension 在 MAIN world 注入同一解析脚本，覆盖所有 http(s) 子框架，与 Android document-start 注入范围一致（插件 forMainFrameOnly 仅对 iOS/macOS 生效）。内容桥接是只读候选输入，并由当前 session/generation 和生产 URL 校验隔离。尚不支持 `useLegacyParser=true` 的 iframe-only 模式，显式失败，不悄悄改变规则。

固定UA取自 App 的 `userAgentsList` 第一项，仅应用于浏览器解析和媒体请求；搜索/集表仍走原规则请求实现，空UA可能随机取桌面列表，因此另行核对两组剧集页摘要。初始手机UA实验发现7sefun跳转App下载页，已保留并排除出代表App的比较。诊断补充后必须重测跨域 iframe，用它区分桥接覆盖缺口和真实内核兼容失败。扩展脚本变化时更新 manifest version，避免复用旧内置扩展注册。

两个内核都关闭网络图片；Gecko使用内置扩展阻止 image 请求。APK 为 Flutter debug 包（原生依赖可能包含其他 ABI），本轮只执行 x86_64；不可把包大小或 debug PSS 当生产开销。

现代模拟器不能证明 Android9/WebView66/ARMv7 电视兼容；本轮不操作电视，不绕过站点挑战。搜索/集表失败通常先排查规则/网络；已确认同一剧集一内核失败另一成功，才是运行时差异线索。HTTP请求响应的逐包对照、热会话/长时间取消压力、最新Gecko及旧Android矩阵仍需后续独立验证。

Android9对应环境：官方 `system-images/android-28/default/x86_64` revision4 自带 `com.android.webview/66.0.3359.158`，与已记录电视内核版本相同。创建专用AVD后须再次核对dumpsys和App报告，不靠镜像名称推定。SDK/内核一致仍不等于厂商系统、ARMv7、GPU/MediaCodec硬件一致；模拟器会按App已有保护选择软件输出，不能验证电视硬解路径。新Android CLI使用斜线包路径；其sdkmanager兼容包装器会把分号路径拆成多个包，可直接用 `android.exe sdk --ignore-outdated-xmls install system-images/android-28/default/x86_64`，无需改全局代理或SDK设置。

规则覆盖会话负责声明式契约，本工具只消费既有 Plugin 规则，不包含第二套覆盖实现；不把 HHJX 兼容补救偷偷转成任意规则脚本。

集成适配入口：清单可以直接传入 `rule: <effective plain JSON>`，无需 `rule_file`。规则候选/集成树负责调用 `plugin.toJson(includeLocalMetadata: false)`；当前分支不导入尚未合入的 RuleOverlay。可附 `rule_provenance: {overlay, base_sha256, effective_sha256, upstream_commit}`，运行器原样携带为调用者声明，同时独立记录输入 JSON SHA256 与运行时 ruleFingerprint；三种摘要算法不应混用。未知上游 commit 必须 null。基础/有效对照各自作为不同案例，禁止修改真实规则列表以构造对照。

官方参考：[GeckoView WebExtensions](https://firefox-source-docs.mozilla.org/mobile/android/geckoview/consumer/web-extensions.html)、[MAIN world 支持](https://blog.mozilla.org/addons/2024/07/10/manifest-v3-updates-landed-in-firefox-128/)。

## 规则覆盖集成候选

集成版rule同时接受生产模型支持的普通规则、覆盖bundle和带本地元数据的导出规则。
rule_variant默认为effective；只有带覆盖元数据时可选base，它构造独立基础对象，不改写已安装规则。
基础/有效对照使用不同case id，其余条件保持相同。运行时observed_rule_snapshot记录实际有效摘要、
基础摘要、覆盖文档摘要及来源标签；摘要统一使用RuleOverlay.fingerprint。
普通纯规则的来源和基础摘要未知，保留null。来源标签未经联网或签名验证；调用者rule_provenance
仍单独保存，不能代替运行时测量。这不新增播放profile或改变默认内核、网页fetch请求头。
