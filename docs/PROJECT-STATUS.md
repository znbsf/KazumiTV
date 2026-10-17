# KazumiTV 当前状态

## 2026-10-17 四项集成实现与本地/设备验收（未发布）

目标：兼容播放继续、首页持久缓存、issue #15 手机扫码输入、issue #19 源健康与首次有限自动选源。四条工作线已合并至 `feat/four-stream-integration-20261017`，工作树 `Documents/Kazumi/workstreams/integration`；个人电视/频道/EPG 不在本次范围。正式数据未动，未推送或发布新版。四项实现与当前可执行本地/设备验收已基本完成；不是正式交付或发布完成，测试环境清理已完成，见下方证据。

| 工作线 | 集成状态与验证边界 |
| --- | --- |
| 兼容播放 | 沿 PR #18 基线 `6ea26223` 集成；保留手动模式、有界恢复、旧会话隔离。真实完整 VideoPage：电视20515和模拟器20514的软件恢复均达到17秒、暂停、1.25倍速；电视继续至EOF正常进入下一集默认mediacodec。模拟器FFV1负向呈现清晰3按钮，无重试循环。延迟请求在途退出后新建会话恢复已验；未覆盖原生新旧响应重叠。 |
| 首页缓存 | 已集成缓存优先、后台刷新、失败保留、更新时间与遥控刷新；分支 53 项定向测试通过。模拟器 20508 受控立即失败/延迟15秒失败均保留升级前真实缓存的10张卡片与11:35更新时间；Android 9 首次真实加载已验。系统离线及封面缓存覆盖不作扩大结论，搜索失败独立诊断。 |
| 二维码输入 | 已集成短时局域网会话。Edge 空输入校验、合法 `Clannad 模拟器` 提交、模拟器即时回显及退出焦点已验；仅证明本次隔离 QA 通路。 |
| 源健康/首次选源 | 已集成有界探测、首帧分级、取消与有限候选。模拟器 feature 20505 与电视 20507 自动探测均收到 firstFrameNotify 并返回有限候选；电视记录含时间、规则版本，取消返回“未选择/取消”。首次 GPU 硬解 ANR 原证据保留，尚不能据此判定根因。 |

验证证据必须绑定源码及环境：

- **最终候选**：生产修复 `7595a9adc55d4579f1edac4b26b9b82c6c70b6ae`，验证 head `606593f1373002860b72eb7d2309f02a859c7433`：**955 项全量测试通过，0 error / 0 warning / 161 info**。见[验证身份与日志哈希](../../../artifacts/four-stream-20261017/integration-validation-final-candidate.json)、[最终候选测试](../../../artifacts/four-stream-20261017/integration-tests-final-candidate.log)、[最终候选静态检查](../../../artifacts/four-stream-20261017/integration-analyze-final-candidate.log)。后续仅文档更新不冒充重新运行。
- `80adb5c7` 加当时 `cupertino.dart` 的 ignore 修改：全量 **947 项通过**，analyze **0 error / 0 warning / 168 info**。这是较早阶段证据；最新候选以955项记录为准。
- `f9c1b734` 统一健康探测与生产播放的 Android 解码配置：Android 模拟器使用 `gpu/no`，**51 项定向通过**；后续 feature 20505 模拟器与 20507 电视已有首帧/有限候选复测，不把合成规则结果推广到所有真实来源。
- `b2e8ba76` 加强 external QA 对异步 position 等状态的等待。旧脚本在 position=0 时输出的 PASS **不算位置恢复通过**。新 external snapshot 20506 在模拟器的严格断言为 position=17s、rate=1.25、playing=false、tracks=true，稳定500ms后 PASS，见 external-asserted。
- API 36 模拟器与 Android 9 电视均已执行隔离 QA；电视 feature 20507 首帧、记录、取消及首页真实加载已验。正式应用数据、收藏及规则未动。

证据根为宿主 `Documents/Kazumi/artifacts/four-stream-20261017`（不在 integration 工作树内）：[全量测试](../../../artifacts/four-stream-20261017/integration-tests-final.log)、[静态检查](../../../artifacts/four-stream-20261017/integration-analyze-final.log)、[二维码浏览器步骤](../../../artifacts/four-stream-20261017/qr-browser/emulator-browser-e2e.txt)、[回显](../../../artifacts/four-stream-20261017/feature-qr-result.xml)、[退出焦点](../../../artifacts/four-stream-20261017/feature-qr-exit.xml)、[健康 ANR](../../../artifacts/four-stream-20261017/feature-health-anr.log)。包身份与构建参数查同目录各 APK 对应 JSON；原始证据留本地，不将日志中私有地址公开。

### 本轮新增设备证据与边界

以下设备结果由集成负责人执行并核对；本文档协助仅汇总证据，不另行操作设备。

- 首页：`7b7fc1bb` 为 `tools/qa/feature_hub.dart` 增加正常真实请求、立即失败、延迟15秒失败三种模式，仅拦截默认热门元信息请求，退出移除拦截并取消等待；生产控制器/磁盘缓存与系统网络不改。模拟器真实缓存时间为11:35，升级到20508后，失败和慢失败仍展示相同10张卡片与相同更新时间；[立即失败截图](../../../artifacts/four-stream-20261017/feature-home-failure.png)和[慢失败截图](../../../artifacts/four-stream-20261017/feature-home-slow.png)已由负责人查看。该证据证明受控刷新失败的持久缓存保留，不等于全系统断网或所有封面均可离线。电视[首次真实加载](../../../artifacts/four-stream-20261017/tv-home-first.png)已验。
- 健康：模拟器 feature20505 与电视20507 自动探测收到 firstFrameNotify，返回有限候选；电视[健康记录](../../../artifacts/four-stream-20261017/tv-health-records.xml)含时间与规则版本，[取消](../../../artifacts/four-stream-20261017/tv-health-cancel.xml)返回未选择/取消。旧[GPU硬解 ANR](../../../artifacts/four-stream-20261017/feature-health-anr.log)保留，不认定根因或将单片成功推广为全站健康。
- 外部恢复：external snapshot20506 的[严格断言日志](../../../artifacts/four-stream-20261017/external-asserted.log)在模拟器确认17s、1.25倍速、暂停及tracks=true，连续稳定500ms后PASS。它证明该隔离原生状态恢复，不替代下列完整VideoPage结果。
- 完整播放页面：生产修复7595a9ad对应电视recovery20515与模拟器recovery20514，均在真实完整VideoPage完成软件恢复至17秒、暂停、1.25倍速。电视随后继续播放至EOF，并正常下一集回到默认mediacodec。见[电视恢复](../../../artifacts/four-stream-20261017/tv-recovery-restored.log)、[模拟器恢复](../../../artifacts/four-stream-20261017/recovery-emu-action-restored.log)及同名PNG/XML；精确包身份查[电视20515](../../../artifacts/four-stream-20261017/recovery_page-android-arm-20515.json)和[模拟器20514](../../../artifacts/four-stream-20261017/recovery_page-android-x64-20514.json)。模拟器FFV1负向[失败状态](../../../artifacts/four-stream-20261017/recovery-emu-failed-visible.log)显示清晰3按钮且无重试循环。延迟请求结果见下一条，按实际时序限定覆盖范围。
- 延迟在途退出：`media-requests.jsonl`记录12:03:12.914发起delay12；旧会话id471688714于12:03:14.728退出，约1.8秒。新会话id3555623于12:03:28建立，已在旧请求预计返回之后；恢复firstFrame于12:03:37.418，12:03:39达到17秒暂停。证据见[请求时序](../../../artifacts/four-stream-20261017/media-requests.jsonl)与[最终恢复](../../../artifacts/four-stream-20261017/recovery-delay-final.log)及同前缀截图/控件树。此结果仅验证在途退出及随后新会话恢复，**不能称原生新旧响应重叠验证**。
- 声画：本轮 [AV2录制](../../../artifacts/four-stream-20261017/external-emulator-av2.mkv)实际检测到440Hz音轨A、字幕B进展；录制音频相对画面延后159–224ms，中位205.5ms。不得称声画同步通过，也不能只凭录制偏移判断播放器根因；轨道状态断言与实际音轨观测分别保留。

无网络变更的自动覆盖仍可复用：`popular_category_cache_test.dart` 用Completer延迟与Dio connectionError验证慢网/离线保留；`home_catalog_cache_test.dart`覆盖首次、容量、损坏、旧schema、过期。可执行单项命令为 `flutter test --no-pub test/popular_category_cache_test.dart --plain-name "slow startup displays cache before refresh; overlapping refresh deduplicates"` 与 `flutter test --no-pub test/popular_category_cache_test.dart --plain-name "offline cold start retains persisted cards and reports refresh failure"`。本次文档更新未重新运行测试。真实搜索失败、封面缓存完整性及电视此前失败根因仍需独立证据。

工程编排 skill：catalog 未列出；用户主目录 `.agents/skills/orchestrate-engineering/SKILL.md` 可读，正文已手动读取，不等于自动加载。TV QA skill 已读取。构建、模拟器和 ADB 仍由集成负责人协调；文档/缓存协助不操作设备、不改变网络。

剩余边界：原生新旧响应重叠未验证（已验范围仅延迟在途退出及之后新会话恢复）；二维码实际Wi-Fi/手机扫码、真实用户番剧全源、物理声画及校准同步尚未验证。首页系统离线/封面覆盖、实际外部音轨选择对应关系不从受控QA或状态断言扩大推断。当前实现及可执行本地/设备验收基本完成，但不能标为正式交付或发布完成。无推送、无发布；测试环境清理已完成。

### 环境清理（2026-10-17 12:05 UTC）

自建API36模拟器与loopback媒体服务均exit0，PID12168/70292已消失；无Flutter/Dart、scrcpy或qemu测试进程。两个设备的featureqa/recoveryqa均停止且pidof为空，临时forward/reverse为空；QA包保留不卸载。电视已回到原com.mitv.tvhome启动器，正式包仍0.4.3/203931，speaker音量8/100、未静音、Awake均与此前一致。直接am start该受保护启动器曾被Android HOME_STATE权限拒绝，未重试或绕过；停止QA后实际前台已自然恢复原启动器，因此没有待解决的界面恢复阻塞。未触碰Quest3、手机、防火墙或正式应用数据。剩余Gradle/Kotlin守护进程仅记录负载，不强杀共享工具链。见[设备清理结果](../../../artifacts/four-stream-20261017/cleanup-device-results.json)、[进程负载](../../../artifacts/four-stream-20261017/cleanup-host-load.json)、[电视最终前台](../../../artifacts/four-stream-20261017/tv-focus-after.txt)。

2026-10-16：稳定版 [v0.4.3](https://github.com/znbsf/KazumiTV/releases/tag/v0.4.3) 已公开为 Latest，0.4.3+20393。标签 `9fb923c26647e944c9107ab3635ce1aca2ccf057` 与 PR #16 的 main 合并 `ab273c1aca02238cf03d6f523dac7ef259e4830b` 完整树一致。main CI 38885389953 四项成功；11项正式附件已匿名下载核验SHA256。ARMv7正式包同签名保数据升级及短播回归完成；其他ABI未作实机验收。

后续 [确认后兼容播放](CONFIRMED-PLAYBACK-RECOVERY.md) 独立开发，仅准备草稿PR，未合并、未发布，不改变 v0.4.3。个人电视/频道/EPG preview 仍独立。

下方记录是既往状态快照，旧授权阻塞、草稿或未合并描述已被本段最新事实取代，不据历史状态继续操作。

## 历史状态记录


2026-10-15 后续阻塞修复：main合并提交286ab90d的CI38760304410出现限流间隔33ms（要求≥35ms）失败，APK跳过。已确认旧算法存在早醒/迟到放行漏洞，正在PR #13补入单调时钟及实际放行间隔修复，详见[故障与回归](RATE-LIMITER-CI-20261015.md)。后续以含修复的最新head为准，不能沿用旧INFO head的CI。公开issue #11状态更新被自动审批拒绝，尚未修改；PR #12已合并，未发布。

2026-10-15 16:24 UTC：用户明确批准后 INFO 分支推送成功，已创建 [草稿 PR #13](https://github.com/znbsf/KazumiTV/pull/13)，目标 main；下文推送阻塞已解除。源码仍为 b3055c3d，877项本地测试及电视验收记录不变，远端CI待完成。未合并INFO或发布；后续以该PR精确head的检查结果为准。

2026-10-15 INFO 本地交付：`b3055c3d` 完成精简卡片，877项全量测试、静态0 error/0 warning（58 info）、ARMv7独立QA构建及Android 9电视开关/焦点/播放状态验收通过，见[INFO验证记录](STABLE-INFO-VALIDATION-20261015.md)。远端推送被自动审批拒绝（需要明确推送/建PR授权），尚无INFO PR或CI结果，未合并INFO或发布。PR #12已经合并，不能与INFO待交付状态混淆。

2026-10-15 后续授权与状态：PR #12已正常合并至main，merge SHA `286ab90d7f59279fdd01675002cad4b3eacf6b41`，未发布。精简INFO在独立 `feat/stable-playback-info` 实施，范围、源码依据与测试计划见[INFO方案](STABLE-INFO-PLAN.md)。下方“草稿/未合并”是合并前历史记录；当前INFO不引入频道/EPG/排期，后续仅建新draft PR，未授权合并INFO或发布版本。

2026-10-15 最新核对：PR #12 head `ab5ea883a08708cf2a291269c88468273bed7295` 的 [CI 38746978591](https://github.com/znbsf/KazumiTV/actions/runs/38746978591) 于14:12:31 UTC全部成功：871项测试，静态0 error / 0 warning、58 info，三ABI构建与产物校验通过。PR仍为草稿、未合并、未发布。QA生产代码仍对应 `dae2bbede53f225a3f0c135181f0981f502ddcce`；下方869项为旧head结果。验收边界及正式升级/签名/附件待办见[稳定发布准备](ISSUE11-RELEASE-READINESS.md)。

独立设备研究见[桌面/ADB状态与回滚](TV-DESKTOP-ADB-STATUS.md)：LTv普通入口可用，Home Button Fix已关闭，临时设置包状态已恢复，原HOME保留；开机启动、HOME接管与ADB持续可用分别记录，不作为稳定版已修复功能。

2026-10-15 第二阶段补充：新增超时后取消/重试及连续换源历史身份回归，七文件70项通过；Android 9换源取消前后暂停位置90444ms一致、焦点回设置，正常退出后媒体会话清空。没有新增生产代码修复；实际超时与纯遥控取消仍有未测边界，详见[第二阶段记录](ISSUE11-TV-STAGE2-20261015.md)。

2026-10-15 维护验收：PR #12程序head `dae2bbede53f225a3f0c135181f0981f502ddcce` 已通过869项CI及三ABI候选校验，API36模拟器和Android9独立QA核心链路已有实测。纯遥控及长播补充结果见 [第一阶段记录](ISSUE11-TV-STAGE1-20261015.md)，前序范围分别见 [模拟器记录](ISSUE11-EMULATOR-QA-20261015.md) 与 [电视首轮记录](ISSUE11-TV-QA-20261015.md)。候选仍为草稿，未合并、未发布；不能把未测的完整搜索链路、纯遥控加载取消或音画同步写成通过。维护时使用 [项目TV验收技能](../.agents/skills/android-tv-ui-qa/SKILL.md)。

2026-10-14 维护更新：[#10](https://github.com/znbsf/KazumiTV/pull/10) 已以 `ae2d9dab5b036cdde568d6b714ce498fb75a7a3b` 合入 main，显式换源代码已集成，但未发布新版本；其原设备验收边界仍有效。[#11](https://github.com/znbsf/KazumiTV/issues/11) 单独追踪 API 9、设置导航、控制栏动画和 WebView 卡住回收修复，当前为候选分支。规则说明见 [RULES.md](RULES.md)。已发布版本仍是下面的 v0.4.2。

本文件是仓库唯一当前状态入口。历史报告保留原始事实，不从旧结论恢复授权或状态。更新日期：2026-10-15。

## 历史发布：v0.4.2

- 正式版：[v0.4.2](https://github.com/znbsf/KazumiTV/releases/tag/v0.4.2)，Latest，非草稿/预发布。
- 标签对应源码：`590001e970e637622422908a9a2e1dcc0d54a999`；0.4.2+20392，三ABI versionCode 203921/203922/203924。
- 正式包名 `com.znbsf.kazumi.fluttertv`，长期证书SHA256 `3225e3b8676eed2d2f28fad6255881120f6335ade615bbb27673d974727ce806`。CI `.candidate` 为独立开发签名包，不是正式附件。
- 11项公开附件已实际匿名下载并逐个通过SHA256，含三ABI APK/验证JSON、精确源码ZIP、许可归档、LICENSE/NOTICE和SHA256SUMS。
- 正式版本地846项全量测试通过，静态0错误0警告58 info；[CI检查和三ABI构建](https://github.com/znbsf/KazumiTV/actions/runs/38404754840)全部成功。
- ARMv7正式包同签名保数据升级、启动、输入法导航/编辑/Back/取消和滑条调值恢复smoke通过。此前同一生产逻辑候选完成代表性电视/模拟器回归；未把所有调用点或所有网站声明为全测通过。
- 发布源码与本地构建提交只差Git作者元数据，完整树一致；各APK验证JSON明确记录对应关系。后续纯文档提交不改变APK源码和标签。

## 本版范围与后续

本次只发布原功能bugfix：#1当前项目入口，#3滑条/seek，#4输入，#5主题，#6焦点/缓存/长说明/设置消费及数字快捷角标，以及#8标准/小播放器跳过秒数输入校验。详见[0.4.2记录](RELEASE-0.4.2.md)。

个人电视、频道、EPG、LCN等新功能（#2）及新频道数字选台不包含在本版，个人电视数字表单亦不包含在本版，开发成果独立保留。#7网站验证码兼容继续跟踪；原有验证能力已继承，不承诺所有来源、多阶段挑战和API/章节验证均可用。

ARM64/x86_64正式包只完成构建、签名和产物校验，未作实机验收。整集长播、全部设置业务分支、登录/同步/评论/建房等没有完整实测结论。源码、配置或设备环境变化后按影响范围重新验证。

## 维护入口

- [构建与发布流程](TV_BUILD_AND_RELEASE.md)
- [工程经验](ENGINEERING-LESSONS.md)
- [数据与迁移](TV_DATA_MIGRATION.md)
- [原生依赖对应源码](NATIVE_DEPENDENCY_SOURCES.md)
- [历史归档](history/README.md)

本次0.4.2授权仅覆盖本次纯修复发布；不恢复旧任务权限，也不自动授权未来版本、新功能或新设备操作。
