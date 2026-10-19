# KazumiTV 工程经验

## 2026-10-20 浏览器内核比较的准入条件

- 服务级batch默认复用实际工厂及整个播放控制器；受控内核A/B另列profile。强制现代解析器会绕过旧WebView原生拦截与补救，不能声称等价App。真实UI还要从正常main入口按DPAD确认，不以内核测试页面代替。此次Android9/WebView66已复现403并验证补救，也发现现代通过、旧环境超时的另一集；结果见[状态](PROJECT-STATUS.md)。
- 旧版本环境先查官方镜像，不预设必须提取电视APK或手工降级：API28 AOSP x86_64 revision4实际自带66.0.3359.158，系统provider与App回读均须一致。SDK/内核版本匹配不抹平ARM、厂商系统和解码器差异。官方SDK新CLI的分号兼容包装器拆包错误不是网络失败，优先用其原生斜线包路径，禁止为此改全局代理。
- 用实际播放控制器会暴露fixture自身缺失的HTTP行为。本轮MP4本地服务补齐Range/HEAD以支持真实播放器seek，保留原失败日志；不通过关掉App行为让fixture“通过”。

- 固定UA须取自App实际配置。7sefun对手机UA跳下载页、桌面UA返回播放页；这种失败先归测试条件，不归内核。保留最终URL/页面结构的有界对照，不重新走电视403路线。
- 不能只看跨平台参数名判断注入范围：当前inappwebview插件的 forMainFrameOnly 仅iOS/macOS有效，Android document-start注入全部匹配框架。Gecko要同等覆盖并通过跨域iframe正例后再比较来源成功率。MAIN world桥接仍按当前GeckoSession和代次隔离，候选经原URL校验。
- 相同案例必须核对剧集页摘要、规则内容、UA与实际provider；进程冷不代表DNS/扩展安装冷。PSS要记录进程覆盖、采样间隔及缺失；debug整包峰值不能当正式版内核增量。未执行/无匹配/解析/首帧分开；本次结果与撤销假设见 [当前状态](PROJECT-STATUS.md)，复用工具契约见 [批量QA](../tools/qa/source_batch/README.md)。

## 2026-10-18 故障分路与固定测试签名

- 先依据同一次失败的session/output与该版本解码配置分路；SurfaceTexture只表示输出承载方式，不能单独证明GPU或具体硬件decoder。已确认的QA6用户失败为direct MediaCodec请求，详见[原始行号与边界](CONFIRMED-PLAYBACK-RECOVERY.md)。copy/GPU模拟器历史按原适用环境保留，不自动重开或变成本轮阻塞。
- Surface可用、尺寸、真实帧和正确画面是不同证据。仅direct提前挂载的修复保持；新增GPU同wid重建已撤回，成功与失败记录均保留在原播放runbook，不靠一次首帧事件覆盖视觉失败。
- 临时CI debug证书每次变化导致同包名也无法升级。QA6-r2起使用明确公开、不具身份信任的固定测试签名，限制到remoteqa，CI校验指纹；[构建与升级规则](TV_BUILD_AND_RELEASE.md)。正式密钥与权限不变，不为测试包默认设计数据迁移。当前用户决定测试包无需迁移，设备验收由用户次日进行；过去迁移建议仅作历史，不再作为行动计划。
- 本次仅核验Kazumi及当前Flutter工作树文档，未核验其他仓库。入口AGENTS应可直达状态、播放runbook及构建runbook；更新后实际读回并检查目标存在，不能只写artifacts便声称沉淀完成。

## 2026-10-15 补充回归与设备研究

- 超时恢复串联验证“超时→重试中取消→再次重试成功→旧请求迟到失败”，并检查集数/恢复位置。已接受后退休的播放器允许最终历史写入；核对捕获的来源身份与写入顺序，不能假设所有旧历史回调都应丢弃。它与未接受候选不同。
- CI绑定精确head；生产源码未变时复用明确对应的QA证据，测试/文档变更不冒充新APK实测，不因纯文档重复本地构建。候选CI包不代替正式同签名升级。见[发布准备](ISSUE11-RELEASE-READINESS.md)。
- 开机广播、待机唤醒、HOME接管和ADB常驻分别验证。enabled/bound不证明HOME交付，持久端口不证明adbd常驻，框架崩溃与断连相邻不等于根因已定。保留原桌面恢复入口，不重复失败实验或由历史文档恢复授权。
- 桌面工作先读[状态/回滚及来源](TV-DESKTOP-ADB-STATUS.md)，再按[TV QA技能](../.agents/skills/android-tv-ui-qa/SKILL.md)核对当次授权和状态；无现场恢复条件不试重启/开机。公开记录只留结论和源码依据，设备地址、服务清单及原始日志留在私有证据中。

当前版本和工作状态只在[项目状态](PROJECT-STATUS.md)维护。本页保存可复用方法，不是自动执行计划。

## 稳定原则

- 接口403先核对正常构建是否传入已获授权的配置，不先认定未申请权限。只记录配置路径是否存在、字段是否非空、构建参数是否传入；不读取/输出secret值，不将原始配置、签名凭据或完整认证头放入源码/附件。客户端注入不能保证秘密不可提取，实际分发仍遵守授权范围。
- APK、源码、包名、ABI、versionCode、证书、设备实际加载和测试输入必须关联；文档提交不能冒充程序构建提交。CI成功不等于正式签名或实机验收。
- 保留数据升级必须同包名、兼容证书、递增版本号；先验证安装身份，使用覆盖升级，再核对UID/首次安装时间/数据目录及真实收藏、历史和设置。不同实验包并存不等于数据迁移成功，不卸载/清数据来掩盖升级问题。
- 弹幕异步请求用代次隔离；取消、切集、退出和新请求到来时，迟到成功/失败不能污染新状态。旧对话框取消不能取消新加载。用可控迟到响应测试，区分成功、取消、自动替换、乱序和失败。
- 历史入口需要真实挂载路由上下文，不能只测按钮回调；验证从保留历史进入对应集数，再返回。
- TV布局以实机同屏内容、标题可读性、焦点边界和滚动恢复验收。缩小封面时同时缩短卡片/页头冗余；正常字号及放大字号分别检查，不能靠截断长标题挤密度。
- 图片清晰度先对照实际运行API的字段URL、原图尺寸、代理变换和物理显示尺寸；不同API的medium/small含义可能不同。逻辑尺寸×DPR是解码目标，不能给200px源补出细节。大首页用足够尺寸，小卡用缩略图；详情接续实际已显示URL，保留有界缓存。
- 截图只能证明可见状态，不能证明音量/口型；用户听觉确认与截图、日志、CI分别记账。对比图保留原图，不能把旧版本截图当新包验收。

## 环境参数（使用前核对）

- 本轮主机DESKTOP-MPQC46G，PowerShell；Flutter3.47.3 / revision e8113bf45620cbeb8aff64947ee4c93e16adb4cf，JDK21、AndroidSDK36、BuildTools36.0.0、NDK28.2.13676358。
- 正式身份和证书见项目状态；机器路径、设备地址、进程所有权和私有配置位置是环境信息，不能从本页推断仍有效或已有操作授权。
- TV截图实测1920×1080、DPR2；首页封面约324物理像素。不能由此承诺4K或所有设备相同效果。

## 2026-10-10事实与证据

| 阶段 | 已发生的事实 | 适用边界 |
|---|---|---|
| 20333 | 既有合法认证配置一直存在，但构建漏传dart-define-from-file，自动/手动弹幕403 | 不能将所有历史403归于同一原因 |
| 20334 | 恢复正常配置注入，自动匹配/手动搜索/评论200、实机弹幕可见 | 私有配置源文件不公开 |
| 20335 | 修复历史快捷入口挂载 | 保留已有恢复逻辑，不重做播放器 |
| 20336 | 小海报使1080p时间线显示两列三完整行；16sp标题、评分同排、紧凑页头 | 144/145/147/148/150为该包焦点与日期截图 |
| 20337 | 发现实际p1/镜像medium为200px，common为400px；完成中间构建 | 未正式签名或安装，不能作交付包 |
| 20338 / 9f5fe263 | 首页400px图源，详情承接实际已显示封面；24张/32MiB显示缓存保留 | 160时间线、162首页、167播放、168日志、170暂停、171退出 |

发布附件、hash和验收边界见[发布记录](RELEASE-0.4.1.md)；本地截图/日志原件保存在独立证据目录，公开文档不夹带用户数据。旧结果保留原始版本，适用性不明时标记needs_recheck。

整理方法参考：[orchestrate-engineering v1.1.0，固定SHA fa5991f](https://github.com/znbsf/codex-personal-skills/blob/fa5991fb6eed39600505c38c1069df95dd636cf9/skills/orchestrate-engineering/SKILL.md)。仅采用证据关联和分层方法，不由该skill新增权限或安装工具。
# 2026-10-14：稳定上游移植（#11）

- 审查目标 SHA 不代表整仓已合并；先逐文件核对已移植能力，再选择最小改动。TV fork 不直接 rebase 已共享 main。
- WebView 超时必须覆盖 load 与 parser；取消后旧 load/unload 也可能不返回。先移除事件订阅，有限等待后退出复用并尝试释放，防止旧操作堵住串行队列。此次不覆盖 init 卡住，不保证底层原生资源最终释放。
- 回归用可控 Future 复现旧代码失败；测试 load 不返回、取消后的下一请求、unload 卡住和迟到失败，同时保留早到解析事件与正常复用测试。设备行为仍需独立验收。
- 当前状态只更新 PROJECT-STATUS.md；规则教程见 RULES.md。不要将候选分支或合成数据测试写成已发布/真机通过。

## main 合并前固定检查

每次合并重新执行 [main 保护与合并检查](MAIN-MERGE-CHECKLIST.md)，不能把其他 PR 的授权、旧 head 的 CI 或仅凭 `mergeable=true` 当作当前 PR 可以合并的依据；当前会话已明确授予的有效授权继续适用。规则可在任务期间变化；读不到保护配置必须报告权限限制，不能视为没有保护。


## 2026-10-17 首页缓存候选（待集成与设备验收）

- 代码证据：`BangumiApi.getBangumiTrendsList` 捕获异常并返回空列表；首页空列表不能直接证明断网。网络、接口、解析及搜索失败需要各自日志证据，不以缓存命中替代根因诊断。
- TV 热门首页采用公开元信息缓存优先展示、每次冷启动后台刷新、手动刷新失败保留内容和上次成功时间。只持久化默认热门首页；分类仍使用既有 8 类、10 分钟的内存 LRU。
- 缓存 v1 按直连/镜像隔离，每份最多 96 条、1 MiB；6 小时显示较旧，30 天后丢弃。未知 schema、未来时间、损坏/超限缓存按可再生数据失效，不迁移用户收藏/规则。写临时文件后替换；磁盘故障不阻止网络展示。
- 仅白名单公开卡片字段落盘；不存请求头、账号兴趣、凭据；封面 URL 剔除 userinfo、query、fragment，封面文件继续复用已有图片缓存和权限，不另行抓取或新增权限。没有缓存过的封面离线仍可能缺图。
- 同提供方的首页加载/刷新共享进行中的 Future；刷新成功替换旧列表，失败不清空；提供方切换时丢弃迟到磁盘恢复结果。分页保持原 1008 条上限。
- 可执行验收：首次无缓存启动；在线后退出再离线启动；慢响应期间旧卡片仍可导航；手动刷新空响应/网络失败后卡片和时间不变；恢复网络刷新后更新；损坏/旧 schema 自动重建；镜像切换不串数据；遥控由分类栏最右进入“刷新首页”，左/上返回热门分类。自动测试文件：`home_catalog_cache_test.dart`、`popular_category_cache_test.dart`。真机视觉、焦点及离线封面需集成负责人安排，不能以单元测试代替。
- 本地验证：2026-10-17，`flutter test --no-pub test/home_catalog_cache_test.dart test/popular_category_cache_test.dart test/tv_popular_scroll_test.dart` **53 项通过**。覆盖 7 项持久缓存、22 项控制器、24 项 TV 滚动/焦点，包含刷新入口方向键到达与返回。后台落盘串行执行，不延迟加载完成/焦点恢复；导航假时钟测试使用内存缓存替身，真实磁盘由缓存和控制器测试覆盖。首页标题区复用既有高度展示更新时间/刷新按钮，热门页摘要让位于状态，分类摘要保持。未构建、安装、真机或模拟器实测，不能标为交付完成。

## 2026-10-17 真实首帧与加载界面互锁

- 输出尺寸、Resize、open返回与首帧不是同一证据。尺寸推断曾掩盖完整VideoPage在loading时卸载Video、又等待真实首帧才结束loading的循环；同素材独立GPU/no入口可首帧是定位对照，不证明完整页通过。修复后仍须等原生firstFrameNotify，并核对真实画面与状态。证据及20511/20512失败→20514/20515通过的边界见[播放恢复记录](CONFIRMED-PLAYBACK-RECOVERY.md)。
- 首帧等待期间保留底层Texture实际挂载/绘制及上方加载取消入口；避免Offstage/不挂载或完全不透明遮挡导致无法呈现。此实现使用0.99黑遮罩，测试检查真实Video/Texture/TextureLayer；只替代原生元数据的widget测试不能证明原生首帧。
- 手工Observable的setter必须自己进入action，getter保持可追踪。严格MobX回归要调用生产发布/异步替换/stop清理路径，不用测试外层runInAction包住业务写入来掩盖调用错误。
- 原生seek/轨道命令返回先于类型化事件更新。QA只有轨道匹配不够：位置、倍速、暂停及未完成状态达到目标并稳定后才报PASS；旧position=0的过早PASS保留为无效位置证据。内部音视频录制可验证音频存在和记录内偏移，不代替物理听感或校准同步。


## 2026-10-17 更新检查版本前缀缺陷（核查与修复候选）

- 本次 integration 的 updater/policy/version 工具相对本地 `origin/main` 无差异。`ProjectUpdatePolicy.canCheck` 仅允许 release、TV、纯 `x.y.z`，故 `0.4.3-qa4=false`；这只是版本门禁，没有按包名识别QA。`acceptsRelease` 接受可选 `v` 前缀，但随后 `needUpdate` 直接 `int.parse` 每段：`0.4.3→0.4.4=true`，`→v0.4.4` 与 `→v0.4.3` 均 FormatException，见[复现日志](../../../artifacts/four-stream-20261017/update-policy-repro.log)。负责人核对当前发布tag为 `v0.4.3`，因此正式检查可遇到此不一致；不能把异常当“已是最新”。
- 当前正式路径仅GET `znbsf/KazumiTV/releases/latest`，返回更新信息时assets/安装类型为空，仅查看详情，空assets拦住安装。旧 `legacyAndroid` 匹配仅要求文件名含android且以.apk结尾，不校验ABI；虽然存在OpenFilex路径，不能据此声称正式流程已支持自动安装，也不能为修版本检查而放开该屏障。
- QA4 CI为临时debug签名，无持久签名配置；正式tv.gradle的tvSigned使用长期证书。QA门禁、正式/QA包身份、ABI和签名须分别核对，不能以版本号或候选APK可安装替代升级兼容证据。
- 最小安全修复建议：在严格验证release tag后统一去除可选前导v，再作无异常的数值比较；非法版本应明确检查失败。补无v/v、有更新/同版/旧版/非法tag及QA拒绝的测试，保留空assets与手动查看详情。未来如设计安装功能，须先建立受信包名、ABI、签名与哈希清单，并单独验收保数据升级；本次只记录，未改生产、未发issue。
### 后续已授权修复

- 旧正式策略允许 `v0.4.3` 标签，但通用 `needUpdate` 对首段直接int.parse，导致检查抛FormatException；此前[复现](../../../artifacts/four-stream-20261017/update-policy-repro.log)中的异常不能当作“已是最新”。
- 应用稳定更新现统一使用 `normalizeStableVersion` / `needStableUpdate`：仅接受三段规范数字、远端可选小写v；拒绝空白、前导零、额外段、QA/prerelease/build后缀，BigInt比较避免数字溢出。非法输入明确检查失败。规则自身两段/多段版本继续使用原比较函数，避免扩大规则兼容性变更。
- release+TV+纯稳定本地版本门禁、draft/prerelease及发布URL身份检查保留；仍仅读取本项目latest，assets与安装类型保持为空、只查看详情。未新增下载/安装渠道、权限、包名或签名迁移，也未修旧legacyAndroid的ABI识别；不将版本检查修复当作自动安装能力。
- 验证：`flutter test --no-pub test/stable_version_test.dart test/project_update_policy_test.dart` **9项通过**，覆盖有/无v、新/旧/同版、非法tag、QA/prerelease拒绝、超大数字及规则旧行为。未构建/设备测试、未推送发布；集成负责人按合并后head继续核验。

## 2026-10-17 规则仓库长列表遥控焦点

- 复现：TV 模式下，首次引导「添加规则」及规则仓库共用懒加载目录；首末规则可安装，中间为已安装规则。连续 Down 停在首行，无法到达尚未构建的末行。短列表可到末行，但安装完成后焦点退回首行。
- 根因：已安装状态把唯一可聚焦按钮替换成静态 Row，长段已安装项没有焦点节点，方向遍历无法逐行触发滚动并构建后续项目；安装中的禁用和安装后的替换也会丢失焦点。不是同意协议或按键注入失败。
- 最小修复：共用 PluginCatalogView 在 TV 保留相同按钮焦点节点，已安装/忙碌时 OK 无操作；保留 SliverList.builder 懒加载及非 TV 原行为，不改全局方向键策略。
- 证据：根 artifacts/four-stream-20261017/rules-focus-before.log（4 个长列表失败）、rules-focus-short-control-before.log（2 个安装后焦点失败）；rules-focus-regression.log（生产 TvLoopTraversalPolicy 下 3 文件 13 项通过）、rules-focus-analyze.log（0 error / 0 warning / 0 info）。新增 6 场景覆盖两个入口、2/24/60 行、540/720 高度、首末互达、安装后焦点、重复 OK 不重复下载、固定底部操作及返回入口恢复。设备验收待集成负责人执行，widget 通过不等于交付完成。
- 拟新 issue 标题：首次引导和规则仓库长列表无法用遥控器越过已安装规则。摘要：中间已安装规则无可聚焦操作，导致懒加载列表末尾不可达；安装后按钮替换又使焦点跳回首项。需保持稳定焦点、首末可达和底部操作返回，并补电视验收。尚未发布 issue；不关联个人电视 #2，源健康列表另归 #19。
## 2026-10-17 输出释放竞态与解码错误分类

- `tv-fourqa-decoder-readonly.log` 的 20:49:23 栈定位到 Android `widListener` 在输出释放后执行排队的 seek。取消监听不能取消已排队 Future；必须先同步撤销输出 owner，再取消订阅，每次 await 返回重新检查，且 native 锁晚到的 disposed AssertionError 只能在该 owner 已退休时作为取消处理。活动 owner 或其他异常继续上报，不粗暴吞错。
- pinned mpv `32a164cc017acab50389f2194f720ccfd0b01a28/video/decode/vd_lavc.c` 的 `select_and_set_hwdec` 可在没有匹配硬件方法时报告禁用软件回退；这个信号单独不证明硬件 decoder 曾初始化失败。`force_fallback` 的明确硬件方法失败才进入手动恢复确认，完整方法名由 FFmpeg codec name 和 method 拼接，例如 `h264_mediacodec-mediacodec`。这仍不能诊断硬件损坏或排除坏源。
- TV 内存日志最低 verbose 用于捕获初始化失败上下文；常规诊断只写 session/output/category/固定 signal，不保存 URL 或原始错误。无匹配硬件、首帧超时、请求/格式错误和已释放会话分别处理；均不能冒充硬件 decoder 错误。默认 decoder 和手动一次恢复策略保持。
- 本轮 playback-lifecycle 基线 31769f00：29 项定向回归通过，包含队列取消、native disposed 精确边界、错误分类负向、首帧结果四态、外部轨道恢复、真实 Texture 挂载、遥控确认焦点和原生首帧 token。analyze 无 error/warning（仅风格 info）。这不是 Android native 实机验收；需集成后验证快速退出/重进、慢源30秒提示、真实硬解错误与正常首帧，构建和设备由集成负责人统一。

- 追加 review 修复：只有 owner 已退休才可静默取消 disposed。当前 owner 的 disposed 或 VideoController 初始化 Future completeError 必须走单次输出失败处理器，abort 首帧等待并显示重试/换源；不能依赖另一个 stream.error 才退出等待。mapper 不拥有会话上下文，不能自行吞 releasedSession。处理器覆盖 current/retired、无 error stream 的初始化失败、晚到失败和正常帧；输出终止后不允许晚到 decoder 日志触发恢复确认。
