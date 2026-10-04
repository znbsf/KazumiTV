# 播放可行性核对与现代 Android 解析器修复

本轮基线为 `e8bd8a3b13440860e4ab672b5a55a11e0a69e72b`（0.4.0）。只处理有复现的播放问题；沿用 Dart 业务和原 media-kit/libmpv，不改首页、不升级解码库、不增加同步 FFI 诊断。独立分支 `codex/playback-feasibility-20261004`；旧工作树及其脏文件保留。

## 来源与版本

实际 Git remote：origin 为 `znbsf/KazumiTV`，upstream 为 `Predidit/Kazumi`。可本地核实的原版基线为 `1b395a501f7712d17adbe77a95af65743bf736f9`（2.3.1）；成熟 TV 起点为 `c54b2fd492a4baa4f5e8d604a2b2c83593ce0cda`。既有上游取舍报告记录审查至 `0ea0bbd455a4ce4d30927f84cd50d1d2b2308a18`（2.3.7），但此对象当前不在本地，部分改动曾按固定 SHA API patch 审阅，不能称为已 fetch 的最新上游。0.4.0 是选择性融合，不等于完整升级官方 2.3.7。

复用依据：[上游取舍](FLUTTER_TV_UPSTREAM_DISPOSITION.md)、[播放修复历史](FLUTTER_TV_OPTIMIZATION_AND_PLAYBACK.md)、[解码排查边界](TV_DECODER_REPRO_AND_LIMITS.md)、现有 `legacy_webview_lifecycle_test.dart`、`legacy_webview_script_execution_test.dart`、`webview_source_early_event_test.dart` 以及 `test_support/emulator_main.dart` 的受控测试流程。

## 链路差距与本轮验收

| 环节 | 已有行为与差异 | 本轮处理/验收 |
|---|---|---|
| 选源与规则 | 规则指定 iframe 或普通视频解析；下载池复用解析 worker，可跨规则切换模式 | 现代 Android 同一实例 true→false→true 及反向切换均须解析正确 |
| WebView 解析 | 旧电视 fallback 已有双桥、session 与签名 URL 保留；现代 Android 仍是原版首次安装脚本/桥的模式 | 先用实类+平台 fake 复现，再复用已有脚本和保护；旧页面不得污染下一集 |
| URL/请求头/cookie | 规则请求按域读取验证 Cookie 并匹配验证 UA；播放解析 WebView 使用随机 UA；mpv 只接规则 UA/Referer，未导出 WebView Cookie | 此限制在原版基线已有；修复签名 URL 重复编码，不推测认证兼容性、不改网络策略 |
| 重定向/HTTP | 共享脚本使用 XHR 的 responseURL、fetch Response.url，video 相对地址先按页面转绝对地址；WebView 页面和 mpv 媒体请求是两段链路 | 既有执行脚本测试覆盖重定向 URL；不据此宣称 native HTTP、TLS 或全部跨域播放器可用 |
| 原播放器与音轨 | 媒体依赖固定 media-kit `994465d9…`；初始化 AudioTrack.auto，Android 仍按设置用 audiotrack/opensles | 本轮不改媒体栈；模拟器声音不代表电视音轨/口型验收 |
| 切集/续播/失败恢复 | 服务已先订阅再加载并等待卸载；历史按集身份保存 | 解析器替换/卸载后晚到事件须丢弃；保留已有服务测试 |
| 真实播放 | 受控 fixture 验证机制，实际来源验证可用性，二者分开 | 单台自有模拟器；不触碰现有其他模拟器或真机，不清数据 |

## 电视与模拟器证据边界

- 历史小米 Android 9 / API28 / ARMv7 / WebView 66.0.3359.158 早期融合包曾三来源解析失败，不能沿用为最终结论：后续 203131 已完成 baimao 第1/2集实帧、暂停恢复、快进退、切集和续播；203191 再验第2集 07:28→07:34。它们不等于最新 0.4.0 全面电视验收。
- 7sefun 的既有失败在 URL 交接前出现 TLS/超时，不能归因于解码器。早期 WebView 语法失败同样先属于解析层。
- API36 x86_64 的 native HTTP MP4/默认硬解问题不能直接推断 ARM 真电视；原模拟器回退仅限已确认的模拟器自动配置。
- 不承诺所有来源/全剧可播，不把 fixture 或 PC HTTP 200 当成电视播放证明。

## 当前执行状态

已完成源码复现与修复：原版 `1b395a…` 到 0.4.0 的现代 Android 文件此前没有差异；修复补齐了旧 fallback 已具备的会话边界。下载池空闲 worker 跨规则复用是模式故障的实际入口，不能误称普通播放器选源每次都共享同一实例。

| 确定性对照 | 修复前 | 修复后 |
|---|---|---|
| 同一实例 iframe→普通→iframe，及反向 | 缺少第二类桥/脚本 | 每次替换自有脚本组，双桥按本次模式处理 |
| A 页面迟到事件抵达 B（offset=20） | 发布 A URL + B offset | 丢弃 A，只发布 B URL + offset20 |
| 嵌套签名 token `a%2Fb%26c` | 变成 `a%252Fb%2526c` | 原始转义字节保留 |
| 退页/销毁后的事件、空参数 | 仍发布旧 URL，空参数抛 RangeError | 安静忽略无效事件 |
| document-start 根节点尚不存在、桥尚未就绪 | 旧现代脚本未覆盖这套检查 | Document 观察器捕捉晚到元素，桥就绪事件补发早期结果 |

新 Android 生命周期测试在原实类上 **7/7 失败**（具体行为断言，非编译失败），修复后与旧 fallback、源服务组成的 **26/26 定向测试通过**；全量 **670/670 通过，无跳过**。共享生产 JS 在 Node DOM 模型执行 10 个场景。它们不是 Android WebView 真运行或真实来源可用性证明。

本地原始日志：`evidence/fusion-checks/test-20261004T045400550137Z.*`（RED）、`test-20261004T045738092339Z.*`（定向 GREEN）、`test-20261004T045923856247Z.*`（全量）。下方真实来源已验证现代 Android WebView 到原播放器的交接。模式往返、人为迟到事件、桥尚未就绪、特定签名转义和重定向矩阵仍是确定性测试证据，不能扩大为逐项 native 实测。现代脚本与原实现一样默认仅主框架注入，未宣称解决全部跨域 iframe。

## 本轮模拟器实播

2026-10-04 UTC，父会话明确“一台”仅限制本任务，其他项目的 AVD 可共存。启动前可用内存 11.67 GiB，按既有所有权脚本启用 `Kazumi_Flutter_Fusion_API36_20261002` / `emulator-5600`，2 核、2048 MiB，Android API36 / x86_64 / WebView 143.0.7499.24。验证原候选签名后只执行 `install -r`，实际安装字节与候选哈希一致；UID、dataDir、首次安装时间及另外两个应用的版本身份均保留。

| 实际步骤 | 观察与结论 | 本地证据（相对本轮 emulator 目录） |
|---|---|---|
| 正常选源→解析→播放 | DM84 的 FX战士久留美解析后进入原播放器，真实画面和 23:34 时长可见 | `47-fx-paused-time.png/xml`、`49-fx-resume-advance.png/xml` |
| 暂停→恢复 | 02:26 暂停约 5 分钟仍不变；恢复后到 02:34，画面变化 | `48-fx-pause-stable.xml`、`49-fx-resume-advance.png/xml` |
| 退出→历史恢复 | 历史页 FX/DM84 入口重新解析；28 秒内观察到 02:44，大于本次进入经过时间，证明非零恢复；不声称逐帧 seek 精度 | `53-history-page.xml`、`55-fx-history-detail.xml`、`56-fx-history-resumed.png/xml` |
| 多集切换与继续播放 | DM84 的 JOJO飙马野郎：第3集 00:41/25:46；遥控选集切第2集 00:06/25:16，再恢复到 00:13；随后第1集 00:05/48:44 | `69-dm84-episode3-playing.png/xml`、`73-dm84-episode2-result.png/xml`、`74-episode2-advance.png/xml`、`77-rapid-switch-final.png/xml` |
| worker 复用 | 第3→2→1集只有首次创建 WebView，后三次媒体 URL 分别交接；未见旧集回跳 | `78-final-runtime.log` 中 05:48:58、05:50:42、05:52:46 的换集段 |
| 失败后恢复 | 7sefun TLS/超时、baimao 媒体打开失败及 DM84 旧 JOJO 解析超时后，仍可退回选源并正常播放上述 DM84 样本 | `18-7sefun-timeout.log`、`35-baimao-open-result.log`、`66-jojo-episode1-result.xml` 及后续成功证据 |

失败分层：7sefun 在媒体 URL 前记录 TLS -100/-107；baimao 第1/2集都解析出不同 URL，但原播放器打开失败。针对第1集地址仅做一次 PC HTTP 请求，返回 404；PC 请求不等于 AVD 的 UA/Referer/网络条件，不能据此断言唯一根因。DM84 的 2012 JOJO 来源解析超时，另一同站多集样本成功。FX 历史恢复截图之后日志还记录一次 TCP read 错误；短程恢复证据不证明长时间网络稳定。弹幕接口 403 单独记录，未当作视频解析失败。本轮没有扩展为解码器调查。

证据校正：`34-baimao-first-frame` 实际是加载态；`44-fx-paused` 仍有选集侧栏，不能证明暂停；`50-fx-return-detail` 实际是来源弹层；`54-history-fx-detail` 实际进入历史管理且未删除；`76-rapid-switch-final` 的快速输入被前置身份断言拦下；`77` 的约 211ms 连点只产生一次有效换集（第1集），不算迟到回调或快速取消隔离实测。暂停证明使用 47–49，历史恢复使用 53、55–56，真实换集使用 69、73–74、77。

原始日志和截图只留本地 `evidence/playback-feasibility-20261004/emulator/`，不发布完整播放 URL。验收摘要和文件哈希见 [证据清单](PLAYBACK_ACCEPTANCE_20261004.json)。候选进程日志未发现 FATAL EXCEPTION、Fatal signal、Unhandled Exception；不以此代替长时间稳定性或人工声音验收。05:53:57 核对所有权后仅关闭本任务 AVD，未停止其他项目模拟器或全局 ADB 服务。

## 候选与交付

程序源码固定于 `13aa3847e5045ad37995f2dc65662b4c4c2bd0f0`；相比全量测试时仅增加 guard 花括号，无行为差异。静态分析无 error/warning，既有命令允许 info。

- x64 release 模式候选：`com.znbsf.kazumi.fluttertv.candidate`，`0.4.0-playback` / `203314`，31,188,728 bytes。它复用既有候选调试证书，未发布；正式签名身份仍固定为本机 `KazumiTV-signing/stable`，不新建密钥、不再询问密码。
- APK SHA-256：`aedbe11272ead7a2b911e379f92b951e2af90c3b0c39619ccdbf1525f06a2473`。原 libmpv SHA-256：`fed6d87e0eaa54b6be12578b31a20f1bd09f6aa9d52b0008e4dc88a5887c5926`，与基线相同。包名、ABI、TV 启动入口、签名及性能探针缺席检查通过。
- 本地 APK：`artifacts/playback-feasibility-20261004/KazumiTV-playback-x86_64.apk`；构建和校验回执：`evidence/playback-feasibility-20261004/candidate-build.json`、`candidate-artifact.json`。八个旧仓库的 HEAD、状态和脏文件哈希前后相同；稳定集成工作树及旧融合工作树干净。
- 实际来源的选择、解析、播放、暂停恢复、换集和历史恢复已完成；特定时序/签名边界的证据层级如上表所述。只合入有源码复现与回归保护的解析器修复，不由来源可用性推导扩大修改。
- 按已有授权审查并普通合入/推送 main；推送前核对远端没有并发新提交，推送后核对远端 SHA 与对应 CI。此轮不创建新发布、不替换已发布的 0.4.0 安装包。交付操作及 CI 最终回执保存在本地 `evidence/playback-feasibility-20261004/handoff.json`。

本轮仅更新自有模拟器中的隔离候选包，未卸载或清数据、未操作真机、未更改代理/电源/系统设置；没有审批拒绝。模型与 Standard 状态沿用父显式创建参数，未声称工具内部验证。固定正式签名密钥和本机加密保存的密码继续复用，没有重建或再次索取密码。
