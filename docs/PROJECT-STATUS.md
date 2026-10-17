# KazumiTV 当前状态

## 2026-10-17 遥控增强自动验收收口（独立本地分支）

最终生产/测试源码 `7e0756cb3a37b2750ae78b853c583f83eb9fd2f7`：全量1044项通过，Node13项通过，analyze 0 error / 0 warning / 171 info。最终隔离 featureqa x86_64 20533 APK SHA-256 `24e880836a35334d0aa63744ca73ae6bda1bdc64b552571ce7920cc660abfb92`，安装回读一致；测试、构建与源码对应，后续仅本文档记录。

- 真实Edge viewport 320×640：clientWidth/scrollWidth均305（桌面滚动条占15px），无横向溢出；DPAD约85.66×50，返回273×50，其他按钮最小60×50。320×320压缩视口下编辑框273×156可滚动到达，输入和确认成功，电视显示“窄屏输入测试”，业务/提交计数均0。此项为压缩视口模拟，不冒充真实手机软键盘/IME。
- 真实新旧会话：旧页面断开后禁用，重新开启得到新端口/随机token，新页面连接且默认不读原文，旧页面保持断开。Dart覆盖旧token的文本/遥控404、跨字段/ABA旧confirm和selection409无回调、重连读取授权默认关闭；Node覆盖旧页面不换token、新页面新target与无selection。
- 播放器真实PlayerKeyboardShortcuts分发链验证Info/Menu/red/green/yellow/blue/playPause七动作、一次效果和同revision重放拒绝；缺失action、shouldHandleAction禁用、isBlocked、EditableText及覆盖路由隐藏，返回恢复。属于widget实际回调验证，未将其冒充浏览器→实际解码器端到端播放。
- 新发现既有冷启动缺口：20532在audio_service先启动Dart而MainActivity通道尚未注册时抛出setActive MissingPlugin。20533复用OwnedMethodChannel所有权，捕获尚未注册并由native ready重申当前active；不轮询、不仅吞错。两项回归验证缺失→ready恢复及dispose后不激活。20533无快照冷启动未再出现Unhandled/MissingPlugin，实体Back关闭连接弹窗并恢复手机键盘按钮焦点。原失败日志保留为remote-followup-initial.log。
- PR #20正文在用户明确授权后单次重试成功，回读仍为draft/head 5e479e68；QA5已交付与本增强未包含边界准确。此增强未推送，未长期配对，未操作电视。

证据目录：`../../../artifacts/four-stream-20261017/` 的 remote-followup-full.log、remote-followup-analyze.log、narrow-confirmed.png/xml、remote-handshake-cold-start/dialog/back.png/xml/log 与 phone-remote-delivery.json。

剩余用户验收：物理手机二维码/Wi-Fi/中文IME和真实软键盘缩放；Android9电视上的实际播放器各额外动作、网络/外部轨道和声画。增强推送/PR或测试包远端交付未获授权；不得据此更改QA5、合并或正式发布。


## 2026-10-17 独立临时遥控与普通原文编辑（本地，未进入 QA5）

分支 `feat/temporary-app-remote-20261017` 从集成 `c18a827c` 建立。新增应用语义遥控服务和页面动态能力；仅支持实际页面操作，不注入系统按键，不提供 HOME、电源、系统音量或 CH 映射。一次一条命令，修订与序列防重放，限流、超时锁和旧上下文隔离。详情开始观看立即调度，避免选源弹层未关闭时锁住后续遥控。

默认不读取已有文本。电视连接弹窗只能本地操作；用户会话授权后，普通编辑框可同步原文与选择区，断开撤销；敏感字段始终排除。仍使用短时局域网会话，无常驻服务/第三方中转/长期配对。

- 全量 1037 项通过（最终布局调整及详情修复后补定向 25 项通过）；最终 analyze 0 error / 0 warning / 171 info；Node 页面 12 项通过。
- 最终模拟器包 `phone_keyboard_navigation-android-x64-20532.apk`，SHA-256 `6aa9a08d99796affb32e15e8708c384787c80254edf51b1945e8d39f8906615f`，安装回读哈希一致。API36 / x86_64 / featureqa，仅合成字段。
- Edge→模拟器回环实测：下/上移动焦点、确认打开输入框、返回关闭弹窗；连接设置时手机无遥控键；本地授权后显示“本机已有普通文本”，追加中文并替换选择区到“本机已有普通文本追验”，电视同步一致；手机确认后搜索执行/提交均 0；切换 URL 显示独立合成原文；敏感字段编辑禁用；本地断开显示“连接已断开或闲置过期”。
- [编辑证据](../../../artifacts/four-stream-20261017/remote-final-edited.png)、[确认后计数](../../../artifacts/four-stream-20261017/remote-final-confirmed.png)、[断开](../../../artifacts/four-stream-20261017/remote-final-disconnected.png)。物理返回/方向键清理测试中敏感测试字段提交计数后为1，不能将后续清理截屏当作手机确认零提交证据；业务执行均0。
- 桌面浏览器已目视十字 DPAD；320px 只有CSS/合成测试，真实窄屏和物理手机 IME、播放器额外按钮仍待人工验收。没有操作电视或持久权限变更。未推送此增强分支。


## 2026-10-17 QA5 已交付核验（修复分支）

用户明确授权后，已将 `5e479e68d381c10cea217133df33403db5d9c746` 推至草稿 PR #20，并创建规则列表导航 issue #21。CI run `39038332936` 的 checks 与三个 ABI 构建均成功。ARMv7 下载、哈希、签名、包名、版本、TV manifest、mpv 与 QA marker 排除均由本机重新核验。

- [ARMv7 下载](https://github.com/znbsf/KazumiTV/actions/runs/39038332936/artifacts/12103631716)：`KazumiTV-QA5`，`com.znbsf.kazumi.fluttertv.fiveqa`，`0.4.3-qa5 / 205301`。
- SHA-256：`5088942ed08baf9032c558ee2c8db00f80c8a522d518f01dc39883fa7c3599c5`。
- CI merge `f6f07c9341cfca3c523f019e2521c860e645bfea` 父提交包含上述 review head，二者 tree 均为 `165fbbb0cb9f9e71f849744148b43b82ac97758c`。
- [本机交付凭据](../../../artifacts/four-stream-20261017/qa5-delivery.json)。未安装用户电视，未合并或正式发布。
- 六组修复：开始观看零健康探测/单成功源；成功历史与健康列表导航；规则长列表焦点；应用级连续手机替换输入；硬解错误分类和旧会话释放；v 前缀更新比较。
- 首次协议由用户操作；真实手机扫码/LAN/IME、硬件失败正例与最终声画仍待人工验收。新临时遥控及原文编辑只在独立 `feat/temporary-app-remote-20261017`，不包含在 QA5。
- PR #20 正文更新被自动审批拒绝：授权只涵盖 push、issue 和 CI。未执行、未重试，待明确授权；此项不影响已验证 APK 下载。


## 2026-10-17 用户实测反馈整改（进行中，替代旧验收结论）

用户要求整体整改并优先模拟器 UI/遥控验收。PR #20 保持草稿；电视正在由用户使用，禁止远程输入、重启、改设置或覆盖安装。旧 QA4 205201 尚不包含本节修复，旧“一次性扫码搜索完成”和“开始观看自动探测”不再是目标行为。

| 问题 / 关联 | 已确认根因与改动 | 当前验证 / 剩余 |
| --- | --- | --- |
| 开始观看擅自探测 / #19 | 无历史分支直接进入自动健康页；改为无成功记录手选，有记录只复用一个已成功源。目标番重新搜索严格匹配后正常播放，失败回手选，无自动请求其他规则。 | 入口及旧工作流7项通过；自动测试核对零请求及单源限制。最终生产包真实跨番待人工验。 |
| 历史成功过24小时失去价值、缺全局选项 / #19 | 原current硬24小时且新失败覆盖旧成功；schema2分开latestAttempt/lastSuccess，全局开关共享已成功记录，旧成功待复验；指纹隔离、环境分层、noMatch不全源判坏。 | 服务与页面39项通过；审查和旧文案更新完成，最终20526短屏显示已复验。 |
| 健康记录不能遥控滚动查看 / #19 | 原ListTile不可聚焦；改稳定记录焦点、自动滚入视野、确认详情和返回恢复。 | 自动测试0/1/128条×360/720高度DPAD通过；模拟器20522遍历128条/详情/返回，20526复验最终分钟时间、短屏完整边框与返回。 |
| 引导/仓库长规则列表不可达 / 拟新issue | 已安装行无焦点，安装后按钮替换丢焦点；共用目录保留TV稳定按钮，仍懒加载。 | 13项通过；模拟器两入口到40项，安装后保持、返回首项与退出恢复。底栏一次异常保留，独立无dump/有dump两次对照和2.5秒idle回归通过，尚不归因。 |
| 手机输入只能搜索一次 / #15 | 应用级连续临时手机键盘、真编辑目标与generation/revision防串写、完整URL、敏感字段排除。普通字段只接收手机本次整体替换草稿，不读取原文或按光标追加。 | 35项Dart、7项网页异步回归通过；20525真实Edge+模拟器连续中文、清空、确认不执行业务、字段切换、敏感排除、主动断开通过。物理LAN/IME仍待验。 |
| 硬解失败判定与释放后seek / PR #18关联 | 收窄明确硬件方法错误；网络/超时/解析独立分类，安全日志先于释放回调。vendor widListener同步撤销所有权、取消并校验异步后操作。当前disposed和failed首帧Future均终止并显示错误。 | 分类及并发回归通过。20528持续慢流真实30秒firstFrameTimeout无软解确认；旧delay12在途退出、新H264约1.6秒内重建并在旧响应返回后正常EOF，无Unhandled。真实硬件方法故障正例仍待现场。 |
| v前缀更新检查失败 | 发布策略接受v但比较直接int.parse；独立稳定版本规范化，保留QA门禁和手动发布页更新。 | 9项测试、静态检查通过，已集成；不新增下载安装渠道。 |

验收须覆盖正常/小窗口/长列表/空态、断网、返回中断、重复操作，并保存截图、控件树与连续观察证据；只有单元测试不算交付。最后统一构建新QA，核对旧包签名与数据保留，签名不兼容不得卸载清数据解决；不自行正式发布。

最新生产候选 `b44276ed`：全量 **1017项通过**，静态 **0 error / 0 warning / 166 info**，证据 `artifacts/four-stream-20261017/remediation-final-tests.log` / `remediation-final-analyze.log`。最终下载包改用QA5独立身份，保留旧QA4数据，CI交付尚待完成。健康20526安装回读SHA256为`765f98647f8443fa50a07d57785277a9f31ece6cb1025870e0e8322be770f5ae`；规则/健康连续观察录像为`health-nav-continuous.mkv`，实际24.984秒，不作物理声画结论。后文QA4与一次性二维码记录是历史证据，不能覆盖本节。

仅QA后续修正82277968另通过1项真实Controller实例化测试；完整生产main20529正常到使用约定首屏，因既有自动审批拒绝代接受约定，未按“同意并继续”、未改持久引导状态，首页后续流程未作为实测通过。详见[播放补证据](CONFIRMED-PLAYBACK-RECOVERY.md)。新规则焦点issue正文已备于本地A/rules-focus-issue.md；创建操作被自动审批拒绝（仅整理建议授权不足以对外提交），未执行，等待明确授权；其余交付继续。

## 2026-10-17 草稿审阅与用户验收包

[草稿 PR #20](https://github.com/znbsf/KazumiTV/pull/20) 覆盖四项集成，PR #18保持原状。远端审阅分支 `feat/four-stream-review-20261017` head `31769f00e2a878860a3e1a98c6ed588ddbdb04b7`；本地完整历史保留在 `feat/four-stream-integration-20261017`。首次推送被GitHub GH007邮箱隐私保护拒绝，未创建远端分支；没有关闭账户保护。改用核实的GitHub noreply身份创建同源码树的审阅提交，生产代码与955项通过的候选保持一致。其后仅增加QA入口、文档与隔离CI包身份。

用户下载包为完整生产入口，名称 **KazumiTV-QA4**，`com.znbsf.kazumi.fluttertv.fourqa`，`0.4.3-qa4`/base20520。该电视已有旧`.candidate`包，因此使用新包名，不覆盖旧候选或正式版数据。仅交付电视需要的ARMv7附件；手机使用浏览器。见[中文人工清单](FOUR-FEATURE-USER-ACCEPTANCE.md)。[CI运行39031960602](https://github.com/znbsf/KazumiTV/actions/runs/39031960602) 的实际APK/回执与校验值以最终下载核验记录为准；此前39031599603因包身份更新已取消，不是通过。

真实站点补证据：giriGiriLove2.5/API9、完整UBW源标题、第1集，主机三次串行HTTP请求后，在API36模拟器单次真实health流程于12:14:37 UTC收到实际纹理首帧并返回候选；未重试、未继续正式播放。见[详细分层记录](SOURCE-HEALTH-IMPLEMENTATION-20261017.md)。此项已补，剩余真实Wi-Fi手机、跨番标准元数据匹配、Android9真实站点及实际扬声器/校准同步不能由该单次成功覆盖。专用模拟器PID75000和QA进程随后停止，没有保留网络服务。

### 已交付ARMv7附件（2026-10-17）

[下载KazumiTV-QA4](https://github.com/znbsf/KazumiTV/actions/runs/39031960602/artifacts/12100932820)（GitHub可能要求登录，保留至2026-10-31 12:33 UTC），[中文人工清单](https://github.com/znbsf/KazumiTV/blob/31769f00e2a878860a3e1a98c6ed588ddbdb04b7/docs/FOUR-FEATURE-USER-ACCEPTANCE.md)。实际下载后已核对manifest、签名、ABI与回执；APK为29,272,007字节，SHA256 `acd453236bbb373cb115e2784ab3c8d498508f26c55f789689b2d4cb4edab861`，包名`com.znbsf.kazumi.fluttertv.fourqa`，版本`0.4.3-qa4`/205201。CI实际源码为合并测试提交`1a348f3bd2c4c8e0367184817522c55613502b49`，对应审阅head`31769f00e2a878860a3e1a98c6ed588ddbdb04b7`；不能将两者混用。CI39031960602四个job全部success。仅提供用户需要的ARMv7包；本次交付未自动安装该新包，用户通过现有USB/文件管理器或已授权ADB安装，不覆盖正式版或既有旧candidate。

交付校验详情见本地[qa-delivery.json](../../../artifacts/four-stream-20261017/qa-delivery.json)。手机仅浏览器使用，最终人工确认扫码实际Wi-Fi/搜索确认/退出失效、跨番首次选源及手动fallback、正常/seek/暂停恢复后的电视实际声画。无需新增发布权限；未创建Release或合并PR。本地完整历史与远端审阅分支分开保留，交付后的本地提交仅记录结果，不改变该APK源码。

### 用户要求安装到电视（2026-10-17 12:41 UTC）

按用户新指令，已将上述同一ARMv7 APK安装到已确认的MiTV-ASTP0/mulan、Android9/API28电视。实际包名fourqa、版本0.4.3-qa4/205201；安装后pull回APK核对SHA256仍为acd453236bbb373cb115e2784ab3c8d498508f26c55f789689b2d4cb4edab861。正式版、旧candidate和用户数据未动；未自动播放或改音量。

启动成功，显示首次四步引导的使用约定页，“同意并继续”默认有焦点。自动审批拒绝代按该按钮：安装授权未明确包括代为接受免责声明/改变持久引导状态；被拒动作没有执行，未重试或绕过。随后截图显示界面被外部推进到第4步添加规则，已安装8条；本代理仅发左右方向键，未确认同意或安装规则，因现场并发操作不将焦点变化归因于独立验收。已停止全部遥控输入，留给用户继续；首页仍未验证。截图：[电视安装后界面](../../../artifacts/four-stream-20261017/tv-fourqa-handoff.png)，对应XML/日志同前缀；[安装与阻塞记录](../../../artifacts/four-stream-20261017/qa-delivery.json)。历史“交付未安装”描述只适用于此前下载交付时点。

2026-10-17 规则长列表焦点候选：rules-focus 工作树共用目录组件保留 TV 已安装/忙碌按钮焦点，继续懒加载。两入口 6 场景及既有回归合计 13 项通过，定向分析无问题；设备验收待执行，未发布。复现、前后日志与拟新 issue 摘要见 [工程经验](ENGINEERING-LESSONS.md#2026-10-17-规则仓库长列表遥控焦点)，不关联个人电视 #2。

2026-10-17 issue #15 最新候选：phone-keyboard 工作树将一次性搜索二维码扩展为应用级临时手机键盘，普通 TV 真编辑态跨字段多次输入、修改/清空、只保存文本的确认；敏感字段排除、既有值不回传、旧目标/版本请求拒绝。7 文件 35 项定向回归通过，13 项文件静态分析无问题；隔离 QA 入口已提供，未构建或设备验收，不复用旧一次性搜索的完成结论。长期配对/大遥控面板仅分阶段设计。详见 [issue15 原记录](ISSUE15-QR-SEARCH-20261017.md)。

## 2026-10-17 四项集成实现与本地/设备验收（未发布）

目标：兼容播放继续、首页持久缓存、issue #15 手机扫码输入、issue #19 源健康与首次有限自动选源。四条工作线已合并至 `feat/four-stream-integration-20261017`，工作树 `Documents/Kazumi/workstreams/integration`；个人电视/频道/EPG 不在本次范围。正式数据未动；已推送独立审阅分支并创建草稿 PR #20，未合并或发布新版。四项实现与当前可执行本地/设备验收已基本完成；不是正式交付或发布完成，测试环境清理已完成，见下方证据。

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

剩余边界：原生新旧响应重叠未验证（已验范围仅延迟在途退出及之后新会话恢复）；二维码实际Wi-Fi/手机扫码、真实用户番剧全源、物理声画及校准同步尚未验证。首页系统离线/封面覆盖、实际外部音轨选择对应关系不从受控QA或状态断言扩大推断。当前实现及可执行本地/设备验收基本完成，但不能标为正式交付或发布完成。已创建草稿 PR #20，未合并、未正式发布；内部测试环境清理已完成。

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
