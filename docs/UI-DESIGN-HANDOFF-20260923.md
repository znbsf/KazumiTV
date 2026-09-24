# KazumiTV 首页与系统入口：UI 设计交接

2026-09-23 方案底稿，2026-09-24 更新；源码核对基线为隔离工作树 C:/Users/hentai/.codex/worktrees/4b39/Kazumi，HEAD c8f1ab3f。本文件记录首页设计约束、接入位置和系统入口路线。首页已实现部分内容，但仍在继续验收；当前证据与未关验收项见[首页实现报告](UI-DESIGN-RESULT-20260924.md)。下文源码行号和原型结论是初期底稿，不代表当前状态。播放工作的范围与证据以[播放可靠性交接](PLAYBACK-RELIABILITY-HANDOFF-20260923.md)为准。

## 后续实施状态（2026-09-24）

首页当前方案是一行双组导航：左侧为设置/搜索/排期/历史/收藏，右侧为节目分类；没有恢复状态的新首页默认选中并聚焦「热门」，功能按钮与分类按钮以字号、字重区分；保留六列并在向下浏览时收起介绍。背景铺满整个窗口；当前只有 Bangumi 竖版封面，故用 Coil 模糊转换铺满全屏，不再叠加边缘清晰海报，避免矩形接缝，并对文字区域压暗。这不是独立横版场景剧照。AniList 当前样本中 3 个热门动画条目有可访问 banner，但 title 搜索不是一对一映射，且 banner 不是逐集剧照；TMDB 图片 API 的无凭证请求返回 HTTP 401，确切来源调查见[实现报告](UI-DESIGN-RESULT-20260924.md)。用户也希望借鉴系统屏保、主屏预览频道，后续可探索可选默认桌面；DreamService、Preview/Watch Next 与 ROLE_HOME 均未接入或启用，本次没有更改任何设备的默认桌面。

## 已确认的首页方案

- 焦点节目的图像覆盖整个窗口，贯穿导航、介绍与海报背后；有可靠横版剧照时优先使用，在文字、导航和卡片附近局部压暗。当前只有竖封面时用模糊铺底加等比清晰封面降级，不假称为场景剧照。
- 导航合为一行：左组为「设置、搜索、排期、历史、收藏」，右组为「热门、日常、原创、校园、搞笑、奇幻、百合、恋爱、悬疑、热血」。删掉重复的「浏览」入口。
- 左组采用小图标与稍小的常规文字，右组采用稍大的中等字重；使用同一字体家族，中间留白或细分隔。已选分类与当前遥控焦点分别表达；经过分类只移动焦点，确认才切换内容。
- 没有恢复目标的首次首页默认选中并聚焦「热门」。详情返回、后台任务恢复和明确的内容直达入口分别处理，不能统统跳回热门。
- 保留六列、节目编号和现有分类内数字跳转语义；介绍适度，向下浏览时收起。最近观看独立成行，无历史时省略。更大背景不要求更高介绍区。
- 横向焦点按视觉顺序移动，热门左移到收藏，收藏右移到热门；导航向下经过最近观看再进入海报，无历史直接进入海报。上移回到已选分类。
- 目标电视优先容纳现有十个分类。若可用宽度不足，右组横向滚动并跟随焦点，左组稳定；不换成两行，也不靠缩小到难读的字号强行塞入。字号和渐变强度留待实机校准。

## 启动、返回与焦点契约

| 触发 | 目标行为 | 接入约束 |
| --- | --- | --- |
| 没有保存状态或内容意图的新首页 | 热门选中且真实焦点落在热门 | 初始化默认值只作兜底 |
| 海报进入详情后返回 | 原分类、页/视口、原番剧卡片 | 用番剧 ID 与滚动状态恢复，不只存卡片索引 |
| 最近观看进入详情后返回 | 原最近观看项 | 保留该行身份；进度刷新不得把焦点移到第一项 |
| 正常 Launcher 入口恢复旧任务 | 恢复原详情、列表或播放会话 | 先恢复导航与各页状态，再决定是否需要首页焦点 |
| 屏保/频道明确点击内容 | 一次性处理该条目的详情或续播意图 | 进程重建不得重复消费意图；不被默认热门覆盖 |
| 原条目已删除或服务端结果改变 | 同分类最近的可用卡片，空列表回已选分类 | 使用明确回退并验证实际焦点；不跳到无关剧集 |

TvApp.kt 当前保存 category、page、selected、resumeEntry、returnCard、returnCardIndex、returnRecentId，并持有 LazyGridState；新首页按真实焦点状态恢复，用户方向键输入会取消旧自动恢复。条目被刷新删除时，按原卡片位置选择最近剩余项，目录为空则返回分类；离开首页时简介 `detail` 请求随 Composable 取消。`home-ui-acceptance` 使用假目录和模拟遥控确认了这几条路径。后续若接入屏保/频道内容意图，仍需增加一次性意图映射，不得让默认热门覆盖它。

原有 [真实搜索进程恢复记录](SEARCH-PROCESS-RECOVERY-20260923.md) 只覆盖记录中的旧电视、正常 Launcher 语义与具体路径；本设计不扩大其通过范围。首页改造后须保留该路径回归。播放器进程恢复当前通过 PlaybackStateSavers.pausedOnRestore 保持暂停，首页初始化不能改变它。

## 最近观看与真正续播：当前行为及接口

| 当前源码事实 | 设计接入要求 |
| --- | --- |
| TvApp.kt:55 按番剧去重、最多两项；:237、:334 最近观看回调只传 Subject，点击打开详情 | 第一阶段仍称「最近观看」，保留详情行为。若后续增加「继续」，必须传完整历史身份并走续播入口 |
| LibraryScreen.kt:125、:133 历史列表调用 onResume(entry)；DetailScreen.kt:129 有继续按钮 | 复用现有入口，不另建仅凭番名猜来源/集数的播放链 |
| LibraryCodec.kt:6 的 PlaybackOrigin 保存 rule、sourceTitle、sourceUrl、roadTitle；HistoryEntry 保存 key、subject、episode、position、duration、origin、updatedAt、kind | 展示模型可简化，但激活条目时不能丢掉来源、剧集键和在线/离线类型 |
| LibraryStore.kt:95 按 key 读取，:96 保存时继承缺失的旧 origin、更新时间；隐私模式或无有效进度不写入 | 首页/系统频道只消费历史，不能因聚焦、查看详情或浏览屏保制造播放记录 |
| PlayerScreen.kt:138 在已渲染视频后保存进度；:182 每 5 秒保存，:206 后台停止、:218 释放时也保存 | 保留播放器作为进度写入者；外部入口激活时重读最新历史，不能使用陈旧的频道快照覆盖它 |
| ResumeScreen.kt:10 在线记录重建 Episode 并进入 PlaybackSessionScreen，离线记录进入 OfflinePlayback | 在线继续解析原剧集页，离线按本地资源身份恢复；临时媒体 URL 不能当永久续播地址 |
| PlayerScreen.kt:212 以 request.resumeKey 查历史；PlaybackStateSavers.kt:32 在关闭自动续播、无效位置或剩余不超过 5 秒时返回 0 | 按既有策略显示行为；「继续」不等于任何记录都会从非零秒开始，也不等于自动推断下一集 |

拟新增的外部入口只区分两种动作：详情使用 subjectId；续播使用应用内稳定的不透明标识，映射回 HistoryEntry.key 后重新读取本地记录。当前 key 对在线内容包含规则名与剧集页地址，不应直接暴露为频道 URI 参数；不要向系统卡片复制 Cookie、请求 headers 或已解析媒体 URL。此映射与 MainActivity 意图分发尚未实现。

记录删除、来源移除、原剧集无法匹配或离线文件缺失时，进入带有明确原因的详情/来源选择回退，保留可用的历史上下文；不得按集表索引换到另一集。是否能从频道直接恢复原来源、原集、进度及暂停意图，必须由主任务验收，不能用「已打开详情」代替续播通过。

## 图片能力与降级

当前 Subject 只有 cover，SubjectMetadata 没有横图字段，CatalogCodec 读取 images.large 并回退 image。还没有经核实的横版剧照提供方、番剧 ID 映射及获取链路；整屏剧照不是仅改布局就能完成的能力。

| 素材/设置 | 首页输出 | 屏保输出 |
| --- | --- | --- |
| 可靠横版剧照 | 等比裁切到整屏，局部渐变，避免裁掉主体 | 同一素材的简洁全屏版本 |
| 只有竖封面（当前目录能力） | 低分辨率模糊封面铺满背景，右侧叠加等比清晰封面并渐隐边缘；压暗文字区域；不拉伸为横图 | 同比例构图或跳过该图；不拉伸成横图 |
| 缺图、错误或离线无缓存 | 稳定暗色底，标题、焦点与入口正常可用 | 使用已有可用缓存；无可用图则暗底 |
| OLED/纯黑模式 | 关闭氛围图与过渡 | 单独遵守用户选择，保留关闭屏保入口 |

接入时建议按 subjectId 提供可选横图元数据，包含来源、比例/尺寸和本地缓存状态；历史与导航序列化继续兼容旧记录。沿用 KazumiApplication 的单一 Coil 加载器与 DeviceResourcePolicy，按显示尺寸解码并限制缓存，不为首页或屏保复制无限缓存。

约 450ms 焦点停留后取图、约 180–250ms 淡入仅为调校起点，未经电视测量。快速移动时取消过期请求；离开首页、进入播放器/验证码或后台后停止首页取图与动画。屏保停止时释放自身工作。失败图片不得触发目录重载或抢回焦点。

## 与播放、验证码隔离

- 背景只读「首页可交互时的焦点番剧」，不能作为 TvApp、DetailScreen、PlaybackSessionScreen、PlayerScreen 或验证 WebView 的重建 key。
- 顶部导航和全局按键处理必须服从当前页面/弹层。播放、来源选择、验证码打开时，首页焦点恢复与轮播停用；验证码关闭后先由所属页面恢复控件焦点。
- 历史进度刷新只更新对应条目文案。不能清除 resumeEntry、改 category、重置首页视口或重建正在运行的播放会话。
- 所有迟到图片/目录结果应按页面与条目身份校验；不能因新背景触发重新解析媒体、重复挑战提交或改变暂停/继续意图。
- 验证码提交、Cookie/POST 恢复、来源更换和异常重试沿用主任务实现。设计任务不增加自动识别验证码或独立网络重试路径。

## 分阶段范围

| 阶段 | 交付范围与入口 | 达到下一阶段的条件 |
| --- | --- | --- |
| A 首页 | 单行分组、六列、独立最近观看、介绍收起；有图则整屏，没有横图也能稳定降级 | 首页与详情焦点闭环、已有恢复路径、播放/验证码隔离通过 |
| B 系统屏保与 Preview 频道 | DreamService 展示缓存剧照，左右切换、确认详情、返回退出；热门 Preview 卡片直达详情 | 共用图片与稳定详情入口已完成；目标系统实际可选/可见、后台可释放 |
| C 系统继续观看 | 依据真实 HistoryEntry 发布 Watch Next；剧集、进度、时长和直达续播对应同一记录 | 主任务完成原来源/原剧集/进度恢复；删除同步、失效回退、暂停策略验收 |
| D 可选默认 Home/Launcher | 在目标固件支持时，由用户选择 Kazumi 作为默认桌面；沿用首页视觉，另有其他应用、系统设置与设备支持的输入源入口 | 具体固件支持正常默认桌面选择、取消选择和恢复；离线、Home/返回、其他应用返回、唤醒与进程恢复通过 |

屏保、Preview/Watch Next 频道和默认 Home 是独立系统集成；默认桌面只能作为受支持设备上的可选模式，普通应用入口继续可用。系统级产品可参考屏保的全屏沉浸展示、Preview 频道的节目卡片和桌面 Launcher 的大屏布局，但不应把三者混成首页内的普通按钮。阶段 B 的内容点击先到详情；收藏/在看状态可用于屏保片单，但不能伪装成真实播放进度。频道使用稳定 ID 增量更新，不反复删除重建；隐私模式不生成新的播放历史或系统继续观看条目，记录删除后撤销对应条目。

平台边界于 2026-09-24 复核：

- [DreamService](https://developer.android.com/reference/android/service/dreams/DreamService) 提供系统屏保；需在 Manifest 声明服务并要求 BIND_DREAM_SERVICE，交互式屏保还要明确处理交互与退出。应用内空闲画面不等于系统已接入。
- [Android TV 主屏频道](https://developer.android.com/training/tv/discovery/recommendations-channel) 从 API 26 提供；Preview 频道卡片由系统桌面呈现。应用可提供默认频道，其他频道通常需用户发现并批准；系统和用户控制显示顺序与可见性，应用频道不能替换系统桌面背景或整个桌面布局。
- [Watch Next](https://developer.android.com/training/tv/discovery/watch-next-add-programs) 与自有 Preview 频道分别接入；Google TV 的 Continue watching 另需 Google 认证，标准 API 写入不能证明该桌面会显示。
- [ROLE_HOME](https://developer.android.com/reference/android/app/role/RoleManager#ROLE_HOME) 自 API 29 提供。能否显示默认 Home 选择、启动器选择和退出入口取决于固件；当前 Manifest 仅有 MAIN + LAUNCHER/LEANBACK_LAUNCHER，没有 DreamService、HOME 或内容直达声明，源码也未检出频道集成。

Launcher 阶段应有独立的 Home 意图处理，避免把每次 Home、唤醒都解释成重新打开热门或自动播放。即使目录断网，其他应用与系统设置仍可操作；正常退出桌面模式和恢复原桌面需要实机验证，不把禁用厂商桌面作为通用流程。

## 代码接入位置

以下路径均相对于上述核对工作树；行号为 c8f1ab3f 快照。

| 文件 | 具体职责 |
| --- | --- |
| [TvApp.kt](../app/src/main/java/org/kazumi/tv/ui/TvApp.kt) :63、:131、:139、:198、:228、:247、:313 | 保存首页状态、约束初始/返回焦点；替换侧栏和分类行；保留网格/编号；拆开介绍与最近观看 |
| [NavigationStateSavers.kt](../app/src/main/java/org/kazumi/tv/ui/NavigationStateSavers.kt) 与 [PlaybackStateSavers.kt](../app/src/main/java/org/kazumi/tv/ui/PlaybackStateSavers.kt) | 保持可恢复身份与旧 Android 安全序列化；首页改动不得覆盖播放恢复/暂停规则 |
| [LibraryCodec.kt](../app/src/main/java/org/kazumi/tv/data/LibraryCodec.kt)、[LibraryStore.kt](../app/src/main/java/org/kazumi/tv/data/LibraryStore.kt)、[LibraryScreen.kt](../app/src/main/java/org/kazumi/tv/ui/LibraryScreen.kt) | 复用历史身份、监听进度变化；外部入口映射/撤销从这里衔接 |
| [ResumeScreen.kt](../app/src/main/java/org/kazumi/tv/ui/ResumeScreen.kt)、[PlaybackSessionScreen.kt](../app/src/main/java/org/kazumi/tv/ui/PlaybackSessionScreen.kt)、[PlayerScreen.kt](../app/src/main/java/org/kazumi/tv/ui/PlayerScreen.kt) | 续播、重取集表与媒体、保存进度；实现与实测由播放主任务负责 |
| [Catalog.kt](../app/src/main/java/org/kazumi/tv/data/Catalog.kt)、[SubjectMetadata.kt](../app/src/main/java/org/kazumi/tv/data/SubjectMetadata.kt)、[MainActivity.kt](../app/src/main/java/org/kazumi/tv/MainActivity.kt) | 补可选横图能力；复用应用级缓存；后续增加一次性内容意图分发 |
| [VerificationScreen.kt](../app/src/main/java/org/kazumi/tv/ui/VerificationScreen.kt)、[SourceScreen.kt](../app/src/main/java/org/kazumi/tv/ui/SourceScreen.kt) | 保留验证/选集模态边界，检查顶栏按键与首页恢复不会进入其焦点域 |
| [AndroidManifest.xml](../app/src/main/AndroidManifest.xml) | 仅在对应阶段声明屏保、内容入口和可选 Home；频道同步与屏保服务为待新增组件 |

## 原型与证据边界

- 当前单行交互示意绝对路径：C:/Users/hentai/.codex/visualizations/2026/09/23/01a0cc79-a19b-78e2-8a04-8351ec9f32a9/kazumi-home-single-row.html
- 详细讨论记录：C:/Users/hentai/.codex/visualizations/2026/09/23/01a0cc79-a19b-78e2-8a04-8351ec9f32a9/kazumi-home-design-notes.md
- 同目录 kazumi-home-layout.html 是已被单行方案替代的早期对照，不作为实施目标。原型用色块、示例片名与示例历史，没有真实剧照、真实记录或播放能力。
- 本任务前序浏览器已验证：1024 宽示意的两组同排且十分类无溢出；初始实际焦点为热门；热门/收藏横向移动；向下收起介绍；第 8 张海报进入详情占位页后返回原焦点；脚本语法通过且未见控制台错误。本次收敛重新核对源码、文档与原型文件存在，未重复运行浏览器。
- 未验证：真实电视字号/裁切与遥控派发、Android 焦点恢复、实际过滤/分页/数字跳转、图片下载解码/内存/动画、真实续播/验证码、系统屏保、频道显示、默认桌面。浏览器检查不能关闭这些验收项。

## 实施验收清单

- [ ] 新首页真实选中并聚焦热门；分类只在确认后加载；两组单排、六列、编号与数字跳转可用；历史为空时上下移动无断点。
- [ ] 海报与最近观看各完成「进入详情→返回→不移动直接确认」闭环；深处视口和介绍收起状态正确；历史刷新/原条目消失有稳定回退。
- [ ] 正常 Launcher 语义下后台回收后恢复原搜索/详情/会话；初始热门不覆盖保存状态；明确的外部点击只消费一次。
- [ ] 横图、竖封面、失败/离线、纯黑四种情况内容与焦点清晰；快速移动/离开页面取消旧图；记录目标电视内存和流畅度证据。
- [ ] 首页改动后，播放进度与来源上下文不丢失；在线播放/离线、关闭自动续播、接近结尾及记录删除按既有策略处理；恢复原集后有真实视频推进，不能只看首帧。
- [ ] CAPTCHA 输入/提交/取消及返回焦点保持可用；取图、历史刷新与顶栏按键不抢焦点、不重建 WebView/播放器；暂停意图及主任务异常恢复专项保留。
- [ ] 到系统阶段再验收：屏保可选且退出释放；频道实际可见、卡片目标正确、增量更新/删除有效；Google TV 和厂商桌面分别记录支持情况。Launcher 另验其他应用/设置、离线可用、正常恢复原桌面。

当前首页设计交付没有阻塞性的用户待决项。横图来源是后续工程调查缺口；工具图标、字号与渐变按实机调校。只有进入可选 Launcher 的设备试用阶段时，才需明确目标电视及是否启用该模式；本轮不切换任何设备的默认桌面。
