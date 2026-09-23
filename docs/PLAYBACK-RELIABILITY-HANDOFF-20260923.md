# 播放通路兼容与异常恢复：执行交接

本文件用于短上下文交接，不要求复制整段聊天。2026-09-23核对基线：`main` / `ef85c0c5`；执行前重新检查Git状态和设备。此轮交付是来源兼容、验证码、网络恢复这一整个阶段，不是三个Release。

## 目标与边界

修复并验收“搜索→验证→集表→线路→播放→异常→恢复原剧集/进度/暂停意图”的完整操作路径。保留主页方向及用户设置、来源、收藏、历史。用户取消整集测试，使用有真实视频推进的短测与操作专项；首帧、受控样本、单源成功均不能代替全项验收。

公开基线为Preview6/code52。内部修复累积，不为每个修复发Preview，不改版本、tag或Release。公开包不得内置私有弹幕凭证。主agent独占电视/模拟器与网络操作，子agent只改约定代码和测试；Gradle也由一个执行者统一运行。不要碰无关未跟踪 `docs/QUEST3-FEASIBILITY-PLAN.md`。

## 已有结果，不要从头重做

- MXdm搜索、历史直达、giriGiriLove人工验证码提交恢复已有通过证据；旧验证码2748已使用，不能重复提交。
- 最终无凭证Preview6：AGE第12集5线路在MiTV WebView66和现代WebView143均完成首帧、推进、拖动、暂停/继续。217单测及lint通过。
- 页面配置发现已有计算属性与字面量变量引用两类回退；导航前后及探测中旧候选必须失效。不要为站点便利删除这些限制。
- 验证已有POST/Cookie恢复、假成功保护、取消、HOME/睡眠暂停意图等受控回归；不等于剩余真实来源已通过。
- 旧电视真实搜索后续页→详情→HOME/进程回收→原详情→搜索视口和实际焦点恢复已通过。不是本阶段优先重测对象。
- 已有白名单播放诊断，不记录URL、Cookie、headers、body、原始异常或用户片名；私有诊断sink不能接入公共报告。

按需读取：`RELEASE-VERIFICATION-20260923-PREVIEW6.md`、`SOURCE-VALIDATION-20260922.md`、`TRANSPORT-RECOVERY-20260922.md`。不要把历史轮次不同APK的通过合并成当前包全部通过。

## 待处理清单

|范围|当前证据|下一步|
|---|---|---|
|akianime第2线|旧/现代均媒体发现失败；第1线通过|比较页面、iframe、请求和媒体发现阶段；不能仅归因旧WebView|
|ezdmw第3线|旧电视媒体探测不是可识别视频/清单；前2线通过|区分错误候选、HTML挑战/错误页、请求上下文及真实媒体响应|
|baimao第6线|现代端发现媒体但连接失败/超时；前5线通过|保留命中的媒体阶段，观测连接/响应证据，不先放大超时或断言源失效|
|7sefun第1线、DM84|较早记录分别HTTP404、522|有限复核当前状态；外部故障与客户端缺陷分别记录|
|dalvdm、LMM、mgnacg、mutefun|本轮真实人工验证闭环未齐|逐源新鲜挑战、用户输入、实际提交、原请求恢复，再短播放；无需验证码时记会话已通过，不能冒称本轮测试了提交|
|真实网络恢复|模拟器真实baimao前2轮失败、后2轮通过；第2轮WebView错误-2|在同一次恢复中比较DNS、HttpText、WebView；物理电视路径单列|

akianime第三方解析页的单独HTTP诊断曾被自动审批拒绝，因页面节目参数发送授权未明确；已向用户提问但未获回复。权限配置变更不等于这项授权被补足，不重试或间接绕过该请求；先做不依赖它的任务。

## 第一包：网络恢复可观测性（建议Sol先做）

先读 `app/src/androidTest/java/org/kazumi/tv/RealTransportRecoveryRegression.kt`、`tools/run-emulator-transport-recovery.ps1` 和恢复记录；生产入口为 `ui/PlaybackSessionScreen.kt`、`playback/WebMediaResolver.kt`、`data/HttpText.kt`。

1. 先补测试诊断，不凭猜测修改生产重试。使用同一次会话已经观察到的原播放页，不引入任意外部URL。
2. 记录单调时间、阶段、恢复尝试序号、网络恢复命令已完成的时间。分别记录Java DNS成功/失败及耗时（不输出地址）、HttpText响应状态/耗时、WebView主框架或iframe错误码及导航代次；公共输出不含完整URL、Cookie、原始错误正文。
3. 对照基线无主动探测轮和诊断轮：DNS/HTTP探测可能改变缓存与时序，诊断轮通过不能直接证明故障已修复。沿用可选诊断开关，标记探测是否实际执行。
4. 首次失败后的一次明确延迟重试只作归因；若首次成功，记录分支未触发，不能写“延迟修复有效”。禁止无限重试、普遍延长超时、清Cookie或放宽TLS。
5. 获得可复现故障后才改最小生产层：网络层、WebView生命周期、导航取消或播放意图中哪一层有证据就修哪一层。保持退出/换集后旧请求不能恢复旧播放器。
6. 交付：diff、诊断字段与隐私说明、测试调用方式、预期失败/成功证据。子agent不操作设备；主agent统一复现、审查和测试。

通过条件：真实来源已有视频推进→受限网络确实导致错误→用户选择暂停/重试→网络恢复→恢复同剧同集，位置在测试既有容差内，保持暂停→明确播放后继续推进；退出/换集/取消不被迟到结果覆盖。保留失败记录，解释前后差异；模拟器通过不关闭物理电视断网。物理电视需先确认能恢复原网络，不能断掉管理通路却没有恢复手段。

## 第二包：真实验证码闭环（Sol修实现，Luna可补限定夹具）

文件：`ui/VerificationScreen.kt`、`ui/VerificationWebView.kt`、`rules/VerificationSession.kt`、`VerificationScript.kt`、`MacCmsVerificationCompat.kt`、`SourcePageChecks.kt`。

按“挑战识别→控件定位→输入→实际提交→请求/导航→成功判定→原请求重放”逐段观测。区分点击没有事件、站点拒绝、验证成功但原请求未恢复；只在证据所在层修复，不用按钮点击成功或URL变化代替验证成功。

验收：输入与提交不被遮挡，遥控焦点可见，返回/取消可用，等待时不抢焦点；错误/过期输入明确反馈；正确人工输入后原方法/body/Cookie上下文恢复且搜索非空，接着集表和短播放。POST、延迟导航、HOME/返回、旧挑战迟到必须保留回归。自动化不得识别或绕过真实验证码。

入口：runner `verification-live`（`source`，最长等待5分钟）；`verification`、`verification-layout`、`legacy-mac-cms-verification`、`catalogue-verification` 为受控专项。`already verified` 只证明现有会话搜索可用。无人填写时及时结束挑战，记录人工步骤待验；不重复等待5分钟耗上下文。

## 第三包：剩余来源归因与最小修复

入口：`FullSourceAudit.kt`（`source-audit` / `source`），`SourcePageDiagnostic.kt`（`source-page` / `source` / 零基`road`）。先定向失败线路，再回归同源曾通过线路与一个不同播放器家族；没有新证据时不反复全17源扫描。

观测按阶段分层：搜索状态→集表/选集→页面/iframe→实际候选→HTTP状态及可识别媒体→播放。HTML错误页不能当HLS；不猜地址、不绕挑战、不执行站点代码进行宿主解密。以原版行为和固定规则为对照，优先修通用能力；候选规则隔离测试，不静默改固定17源或启用状态。

每条记录：源码提交、APK哈希、设备/WebView、规则版本、来源/线路/集数、是否回退集数、失败阶段、修改前后证据、未测项。不可播放的外部来源仍列不可用/待判定，不能用“归因为站点”算播放验收通过。

## 运行与现场

仓库 `C:\Users\hentai\Documents\Kazumi`；Java `C:\Program Files\Android\Android Studio\jbr`；SDK `C:\Users\hentai\AppData\Local\Android\Sdk`；ADB `C:\Users\hentai\Desktop\platform-tools\adb.exe`。

设备上次为TV `192.168.123.217:5555` 和 `emulator-5560`，必须重新枚举。包名 `com.znbsf.kazumi.compose.tv`，runner `com.znbsf.kazumi.compose.tv.test/org.kazumi.tv.TvNetworkInstrumentation`。生产代码 `app/src/main/java/org/kazumi/tv`，测试 `app/src/androidTest/java/org/kazumi/tv`。

构建：`gradlew.bat :app:assembleRelease :app:assembleDebugAndroidTest :app:testReleaseUnitTest :app:lintRelease --console=plain`。无凭证候选显式移除当前构建进程的 `KAZUMITV_DANMAKU_FILE`；不要打印或索取私有配置。debug instrumentation针对release时，新跨包测试入口不要依赖Kotlin internal方法名。

现场证据位于忽略目录 `artifacts/recovery-20260922`；raw/private文件不得提交。设备操作前使用新label的 `user-data-backup`；只读比较用 `user-data-verify`；测试确实新增临时数据时才恢复该检查点并核对。不要清应用数据、卸载、改全局网络或同时运行两个设备控制者。工具返回session_id时持续跟同一session至终止，不能因观察超时重启测试。

## 模型分工及停止猜测的条件

- **推荐GPT-6 Sol high承担日常实施；复杂跨层归因可升max。** 先交上面的第一包，输出可审查证据，再决定生产修复。适合当前主要剩余工作，但仍需项目实测确认，不宣称已证明与更强模型等效。
- **GPT-6 Luna max用于窄任务**：解析现有脱敏JSONL生成矩阵、按明确规则补测试夹具、已定位的单函数修复与边界测试。不要独立决定DNS根因、验证码成功条件或整阶段完成。
- 主agent负责目标和变更审查、设备统一操作、难例升级与最终证据审计。普通日志读取、重复统计不再交主agent逐行处理。
- 连续两次修改未改变原失败证据，或需要跨网络/WebView/会话多层猜测时，返回最小复现、假设表和反证，升级诊断；这是任务交接规则，不是宣告整个目标blocked。
- 每次只传本文件相关小节与必要文件，不复制全聊天。不让多个模型重复通读仓库；失败原因不变不重跑同一昂贵测试。交付报告限于改动、测试结果、剩余风险和证据路径。

2026-09-23核对官方说明：[Sol](https://developers.openai.com/api/docs/models/gpt-6-sol)定位复杂编码/agent工作，[Luna](https://developers.openai.com/api/docs/models/gpt-6-luna)定位聚焦且高吞吐任务，两者支持max。API标准短上下文标价分别为输入/输出每百万token $2/$10与$0.10/$0.50；这不是Codex订阅额度折算，也不能保证同任务token数或总成本降低。采用总输入/输出、重试次数、墙钟时间及独立验收结果评估实际节省。

## 可直接发给Sol的首条任务

请读取本文件“目标与边界”“已有结果”和“第一包”，核对当前Git状态。实现第一包的可选网络恢复阶段诊断，保持无主动探测的基线路径；先不要修改生产重试策略。只改该包必要的测试和主机协调文件，不操作设备、不运行Gradle、不提交/推送/发版。诊断必须有界、脱敏、可取消，保留原有网络finally恢复和用户数据断言。报告diff、验证方法及仍不能据此下结论的事项，交主agent统一构建和真机操作。
