# FlutterTV 输入修复与发布候选证据

产品源码为 `e767f4ac875d201e35e63730c7257a873b48fafb`。电视隔离包为 **203291 / 2.3.1-tv-input-final.2**，诊断探针和 Compose 均关闭；完整 **663/663** 测试通过，分析为 **0 error、0 warning、58 info**。基线证据保存于 **2026-10-02**；**2026-10-03 02:29 UTC** 新增同一最终包的有限实测，长按确认后一次返回原卡，播放器长按和取消的可见状态符合预期，最后退出回首页。今日增量单列如下，未重装或重复完整套件。

本阶段在既有[固定主题背景与五列卡片](FLUTTER_TV_FIXED_SURFACES_CANDIDATE.md)上修复三项输入问题，保留 Dart 业务和原播放器。UI 来源、逐页范围和旧实验复用继续以[融合矩阵](FLUTTER_TV_MAIN_UI_FUSION.md)为准。本页是当前输入候选说明，旧 203191/203231 报告保留其历史测量范围；旧性能百分比不能归给本次修复。

机器可读摘要见 [FLUTTER_TV_INPUT_RELEASE_EVIDENCE.json](FLUTTER_TV_INPUT_RELEASE_EVIDENCE.json)。下文 `evidence/...`、`artifacts/...` 指本机工作区中的文件，并非已发布的 Git 附件。公开摘要只保存必要结果与哈希，不复制设备地址、媒体 URL、原始日志或私密账号标识。

## 最终隔离包与来源

| 项目 | 已核实值 |
|---|---|
| 分支 | `codex/flutter-tv-main-ui-fusion-20261002` |
| 产品源码 | `e767f4ac875d201e35e63730c7257a873b48fafb` |
| 包名 / ABI | `com.znbsf.kazumi.flutterlab.test` / `armeabi-v7a` |
| 版本 | `2.3.1-tv-input-final.2` / `203291` |
| APK | `artifacts/Kazumi-FlutterTV-confirm-final-Xiaomi-isolated-armeabi-v7a.apk` |
| APK SHA256 | `b5e40c8cd8696a35dbfe04899bcb079c46a29157a7954f6c3373278634f852e6` |
| APK 大小 | 31,648,090 bytes |
| 当前开发签名证书 SHA256 | `fe3f74f8c6f7bf2af6edffbed9c0293e37cb876beffa6dd5055b8971542892a4` |
| libmpv SHA256 | `6035ab32a2151c404af75417c97646046cbee3d6612365841378635051ba7825`，原二进制不变 |
| 默认功能 | `KAZUMI_TV_PERF=false`、Compose 关闭 |

安装回执确认实际回拉 APK 字节与候选一致，覆盖升级保留测试包 UID、数据目录和首装时间，原三个 TV 应用状态不变；没有卸载、清数据或降级。最终 APK 二进制中探针标记不存在。文档提交及未来交付 HEAD 必须与上述 APK 构建来源分别记录。

2026-10-02 保存的最终包 smoke 已进入真实视频画面，退出播放器到详情，再返回首页最近观看项；播放未留在运行中。该次本应用 PID 日志中 `FATAL EXCEPTION`、`Fatal signal`、`Unhandled Exception` 和探针标记计数均为 0。该次 probe-off XML 没有可用进度时钟标签，因此这次 smoke **不证明**最终包的播放时钟斜率、声音或口型同步。10 月 3 日的独立增量见下节。

本机依据：`evidence/tv-optimization-20261002/confirm-final-candidate.json`、`confirm-final-installation.json`、`confirm-final-probe-off-validation.json`、`confirm-final-smoke.json`。

## 三项输入修复

| 修复 / 提交 | 触发与结果 | 验证边界 |
|---|---|---|
| 播放器长按取消，`1c2d62c4` | 以前控件失焦或销毁会走 release，并可能错误提交短按 seek。现在取消独立于真实 UP；取消回收键所有权和自身加速状态，不提交 tap seek。触控长按状态保持独立。 | 组件回归覆盖取消分支；真实四窗在 `ae90351a` / 203261，见下节。 |
| 分页期间保留有效焦点请求，`ae90351a` | 五列、24 项且正在 append 时，多一次 DOWN repeat 曾清掉待揭示的第 21 项。现在没有可执行下一目标时保留有效请求；其他方向仍可覆盖，迟到 append 不夺焦点。 | 延迟 append 夹具先失败再通过。旧电视窗口只含三次 repeat，未到该边界，不能算真实复现。 |
| 长按确认只激活一次，`e767f4ac` | 首页确认 DOWN 已进入详情后，Material 默认接受后续 repeat，曾继续激活新页面按钮。TV shell 在普通 Focus/Shortcuts 路由前消费确认 repeat，保留 DOWN、UP 和方向键。 | `select`、`enter`、`numpadEnter`、`gameButtonA` 有组件覆盖；真实 fixed 窗口为 `e767f4ac` / 203281。 |

确认门禁只在 TV 模式生效，销毁时无条件移除注册；非 TV 默认行为不变。Flutter 的其他 early handler 仍会被调用，本修复不声称拦截那些 handler 自行执行的业务。实现和诊断范围见 [输入生命周期说明](FLUTTER_TV_INPUT_LIFECYCLE.md)。

真实确认旧样本 `input-final-source-confirm` 在 `ae90351a` / 203261 接受 DOWN、3 repeat、UP 后，按一次 BACK 仍停在详情“开始观看”。修复后 `confirm-held-fixed` 在 `e767f4ac` / 203281 接受同样五个应用事件，按一次 BACK 回到原首页第 1 卡，目录未变；原生注入均 accepted。固定窗口 SHA256 为 `9111df485205f9ff3de8afa6faf85fa9166e5108d6191fde1d95857388610422`。这是受控注入与已保存路由终态证据，不是物理遥控器硬件验收，也未给未注册的中间控件编造身份。

先失败后通过的回执保留在 `evidence/fusion-checks/`：播放器取消 `test-20261002T185047673889Z.json`；分页 `test-20261002T191835291736Z.json` → `test-20261002T191907357608Z.json`；确认门禁 `test-20261002T194139711080Z.json` → `test-20261002T194230084822Z.json`。确认夹具最初无关的平台 override 清理失败单独保留，未混入产品失败统计。以上修复均包含在最终 663 项套件中。

## 播放器真实输入与速率证据

四窗均来自 **`ae90351a11a0ceba361f7d5642979aba4ac40273` / 203261**，探针开启，资源采样及屏幕录像关闭；APK SHA256 为 `049c903f2fe46e7b6b45fdb8b64ab1ebda96b13433f43dfe499605cba4085677`。后续 `e767f4ac` 只改 TV shell 确认门禁与测试，播放器源码未变，但不能把这四窗重命名为最终 203291 实测。

| 窗口 | 应用事件 | 唯一 forward 结束 |
|---|---|---|
| `player-short-tap` | RIGHT down/up，2 项 | `commitTap=true`、`repeated=false`、`seek=true` |
| `player-held-release` | RIGHT down、3 repeat、up，5 项 | `repeated=true`、`seek=false`、恢复自身基础速率 |
| `player-overlay-cancel` | RIGHT down/repeat，UP 方向键 down/up，RIGHT up，5 项 | `commitTap=false`、`seek=false`；取消先于原 RIGHT UP |
| `player-held-progress` | RIGHT down、17 repeat、up，19 项 | `repeated=true`、`seek=false`，结束后保留约 4 秒观察 |

各窗原生注入 downTime 一致、repeat 连续、DOWN/REPEAT/UP 闭合；过滤 F10 控制键后，与应用 key/type/order 逐项相符，没有 dropped 或 state-read error。控件展开窗的取消发生在显示控件后 **39.578 ms**，在原 RIGHT UP 前 **616.224 ms**；取消后状态已回收，迟到 UP 没有第二次 finish。这里都是同一 Dart 时钟的应用事件间隔，不能解释成原生变速延迟。

长窗使用既有约 1Hz 缓存位置样本：hold 内两个完整区间为 **2.0001×**，finish 后三个完整区间为 **1.0133×**，跨松键区间 **1.7599×** 完整保留。数据支持持续加速后恢复接近正常前进，没有记录误提交 forward seek；不能用稀疏缓存样本排除所有其他 seek 路径或证明硬实时上界。

**typed `player_rate` 是 media-kit 缓存／请求侧回报，不能称为原生确认。** 固定依赖 `media-kit-994465d9bfca3f39d0b41199d16e7fd93fe97881` 的 `media_kit/lib/src/player/native/player/real.dart`，先更新 `state.rate` 并发布 `rateController`，再调用 `_setProperty`。现有 position 也没有底层更新时间；本轮不证明 UP 后 250ms 内原生速率恢复，不新增同步 FFI、native getter 或诊断轮询。

完整离线复核与各原始窗口哈希位于 `evidence/input-lifecycle-20261002/player-actual-window-review.md/.json`；结论为 `SUPPORTED_WITHIN_SAVED_TRACE`，保留 native rate、250ms 上界、连续位置／全部 seek 路径三个 UNKNOWN。

## 首页、背景与性能的已有结论

独立计划下的横向 1→5→1、已加载 48 项纵向 1→21→1 均在已记录范围通过，分别包含 10 个应用事件、9/5 个焦点事件、1/34 个滚动通知；输入含真实 DOWN/REPEAT/UP。它们属于 `14f36aad` / 203241。播放器返回后另一次 `ae90351a` / 203261 横向窗口也通过同一独立计划。分页目录在窗口中变化的旧样本仍只作为诊断，未混进有效固定目录验收。

固定背景和卡片过渡的已有依据见[上一阶段报告](FLUTTER_TV_FIXED_SURFACES_CANDIDATE.md)。2026-10-03 的最终包过渡观察见下节，仅覆盖实际编码帧，不新增全场景视觉连续性声明。

静态海报内部 RepaintBoundary 只做了一次同条件对照：各 51 帧，raster p95 **42.829→43.042 ms**，超预算均 **47/51**；build p95 **6.066→4.282 ms**。主要 raster 指标没有收益，因此实验 `8337cdf2` 已由 `4b6e979a` 回退，不留无效复杂度。单窗不是统计收益或面板帧率。

较早 203231 原生 trace 将本应用长等待收敛到 queueBuffer→SurfaceFlinger waitForever：queueBuffer p95 31.371 ms，其中累计睡眠占 98.25%；43/44 次有对应唤醒记录的服务端等待附近出现 Mali fence 完成。它支持提交同步等待，**不证明具体 GPU 工作根因、fence 所有权或某项视觉效果的责任**。不由此宣称 60fps、消除全部卡顿或扩大解码诊断。依据为 `evidence/render-cause-20261002/poster-boundary-disposition.json` 与 `native-release-203231-own-raster-review.md`。

## 验证、三 ABI 配置构建与发布边界

最终源码测试回执 `evidence/fusion-checks/test-20261002T194400011797Z.json`：663 passed、0 failed、0 skipped。分析回执 `analyze-20261002T194633093358Z.json` 及其日志：退出 0，0 error、0 warning、58 info；早期“32 info”不能代表最终源码。此次仅整理现有结果，没有为文档重跑套件。

本地已实际构建三 ABI 配置候选：冻结 `e767f4ac`，叠加四个已记录的 TV Gradle／manifest／图标／banner 文件，复合来源清单 SHA256 为 `95ab028faeef897112d579c88937f1924c210218acd3d846502ab3bbd3388e3c`。它们使用 **`com.znbsf.kazumi.fluttertv.candidate` / `0.4.0-ci` / 当前开发签名**，probe 关闭、原 libmpv 不变；这不是正式签名发布验证。

| ABI / 版本码 | APK SHA256 | 已有运行验证 |
|---|---|---|
| armeabi-v7a / 203301 | `0b1c5b0df0966dd9a716de7ebd42b2bc7176def6b2b307767d43d58989619997` | 配置包完成构建门禁，未安装；同源隔离 203291 有电视 smoke |
| arm64-v8a / 203302 | `79750d8113dff0d2b3e98e97f7ff09c4140c4d09b3ba651f480bb59677fb1e42` | 完成构建门禁，未运行 |
| x86_64 / 203304 | `8fcf06c4cc8766c3ee9286467a37a0364519943694487058f8bbd439cf79addc` | API36 模拟器同签名覆盖更新，实际 APK 比对通过，首页可见，原应用和候选数据保留 |

模拟器首次安装与引导来自较早同身份 203284；最终 e767 的 203304 覆盖更新单独有回执，不能写成 e767 首次安装测试。模拟器于 2026-10-02 19:57:29 UTC 停止，userdata 保留，未启动 fixture 服务。构建摘要中的 `installed:false` 是构建时状态；后续 x86_64 安装事实以独立回执为准。

本机依据：`evidence/release-readiness-20261002/config-build-confirm/summary.json`、`source-preparation.json`、`emulator-installation.json`、`emulator-final-smoke-and-stop.json`。ARM64 运行、正式签名路径和远端发布 CI 仍未验证；本地三 ABI 构建不能替代这三项声明。

## 2026-10-03：最终 probe-off 包有限复核

复核继续使用已安装的 `e767f4ac` / **203291**，没有重新安装、开启探针或重跑完整套件。先核对已安装包身份、版本、数据及本机 APK 哈希；证书身份沿用此前安装回拉核验回执。正式签名元数据仍无已配置 secret、environment 或注册 workflow，没有读取密钥。

| 场景 | 保存结果 | 边界 |
|---|---|---|
| 长按确认并返回 | 原生 Select DOWN、3 repeat、UP 保持同一 downTime，全部 accepted；一次 BACK 回原第 1 卡。 | probe-off 不提供新的应用内部生命周期流；与昨日诊断流分别记录。 |
| 固定背景与封面过渡 | 设备操作者检查全部 19 个实际编码帧：详情背景不透明，页面与 Hero 按水平过渡移动，未在这些帧中观察到封面闪黑。 | 稀疏 compositor 录像增加负载，无法证明全部物理显示帧、面板撕裂、延迟或 60fps。旧按固定时间取图的脚本超出最后 PTS 失败，随后按实际帧解码，未插帧。 |
| 播放器长按 | 沉浸播放上下文中，RIGHT DOWN、17 repeat、UP 共 19 个原生事件均 accepted、同一 downTime；画面有运动，持键时 2.0× HUD 可见，后续保存帧中 HUD 消失。 | 这是最终包可见状态检查，不是新的原生速率确认或恢复延迟上界。 |
| 展开控件取消 | 暂停状态下持 RIGHT 时展开控件；显示进度前后均为 **23:44 / 24:12**，未观察到错误的 10 秒 tap seek，最后编码帧中 HUD 消失。 | 暂停场景不能替代播放中速率测量，也不证明 250ms 取消上界。 |

首个 `final203291-player-hold` 窗口实际处于选集面板，方向键只移动菜单焦点，**排除出播放器持键／速率证据**。收紧 preflight 为沉浸画面且 UI labels 为空后，仅保留一次有效替代窗口；失败上下文仍保留，不用次数表示进度。

截至 **02:28:19 UTC** 已退出播放器，经详情返回首页最近观看项，未留下播放。原三个应用及隔离包 UID、数据目录、首装时间保持；此次本应用 PID 日志中四类错误／探针标记计数仍为 0。设备测试已收尾，不为完善文档追加验收。

本机摘要 `evidence/resume-verification-20261003/final-smoke-review.json` 汇总来源和限制；各场景回执及帧索引 SHA256 收入[公开证据摘要](FLUTTER_TV_INPUT_RELEASE_EVIDENCE.json)。截图、录像和媒体画面只留本机，不随公开文档上传。昨日四个播放器内部状态窗口仍属于 `ae90351a` / 203261；本节不改写其来源或未知项。

## 发布方案与保护状态

10 月 2 日封存时，main、tag 和公开 Release 未修改，最新产品提交尚未推送；后续融合分支推送由交付回执记录，不改变上述 APK 来源。八个旧工作树的 HEAD、分支、状态和全部脏文件 SHA256 不变，原三个 TV 应用与隔离包数据保留；10 月 3 日最终包复核再次确认原应用与数据保护。

推荐首个 preview 使用新包 **`com.znbsf.kazumi.fluttertv` / `0.4.0-preview.1`**，与原应用并存，不开发旧原生收藏／历史转换层，也不以迁移作为发布门槛。正式版本码及签名属于发布决定，不能把实验包或 CI 候选码直接视为已批准的正式值。

已有只读元数据回执未发现仓库 secret 名称、environment 或已注册 workflow；原生 main 和融合源码的既有 release 配置均使用 debug 签名。尚未确认可直接使用的专用正式密钥；没有读取秘密值、导出私钥或遍历无关本地路径。当前最少发布决定是：采用上述新身份及专用长期签名方案，并审阅实际 main／release 执行顺序后批准发布。候选 workflow 仅在本地，不能当成已启用 CI；其中正式 artifact、main 和 tag 的先后依赖必须在执行前由整合者核对。

main 切换方案保留原生 `24bc50ef47af5e32907ed54413e1eb33c1fb601e` 归档，通过经审阅的双父合并保留历史；需要回退时在新分支／PR 上 `revert -m 1`，不强推。此处是可审阅方案，未执行 main 替换、tag 或 Release 发布。

后续接手先读本机最新交接和运行所有权，再决定是否有尚未覆盖的真实问题。既有 663 项回归、无收益边界实验和已完成四窗不因文档收尾而重复；不要恢复旧定时检查或已暂停的旧会话。
