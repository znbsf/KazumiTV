# KazumiTV 首页界面：继续验收

2026-09-24 · 工作树 C:/Users/hentai/.codex/worktrees/4b39/Kazumi · 验收设备 emulator-5584（Android TV API 36，1920×1080，density 320）。

**状态：继续验收。** 首页单行双组导航、六列网格、全屏无硬边界的模糊氛围背景与主要遥控焦点路径已实现并在独立 AVD 上检查。本轮完成空目录、删除项目回焦、快速分类切换、缓存刷新与离开首页释放简介请求的首页回归。实体电视性能、可许可且稳定映射的真正场景剧照，以及系统级入口仍未关闭；没有构建 release APK。

## 当前设计与实现

- 顶部一行分成左右两组：左侧设置、搜索、排期、历史、收藏；右侧十个内容分类。左侧功能标签 12sp 常规字重，分类 15sp 中等字重并保持同一字体家族；两个组由细分隔线区分。
- 没有待恢复状态时默认选中并聚焦「热门」。焦点返回、保存分类、网格位置恢复和用户输入取消过期自动聚焦仍优先于默认值。
- 六列节目卡片、编号与独立最近观看行保留。浏览到较深位置后介绍区收起。
- 当前 Bangumi 目录只提供 Subject.cover。选中竖封面经 Coil 转换成有限分辨率的模糊图并铺满整个窗口，不再叠放右侧清晰封面，因此没有可见矩形接缝；顶栏与文字区域有压暗处理，六列卡片仍保留。图片 URL、subject ID 和请求代次共同约束加载结果，缺图/OLED 清空，快速切换的迟到结果不覆盖新焦点。
- 这仍是封面生成的全屏氛围层，不是真正的场景剧照。图源调查（2026-09-24）：当前 Kazumi 热门目录取样中，AniList GraphQL 标题搜索为 Re:Zero 第四季 → id 189046、Mushoku Tensei III → id 178789、Grand Blue 第三季 → id 199111；三个条目均返回非空 `bannerImage`，对应 JPG HEAD 均为 HTTP 200，大小 186,382 / 176,046 / 161,498 字节。热门目录里的「ヤニねこ」精确日文搜索无 AniList 动画结果。AniList 官方 API 有 `Media.bannerImage`，但官方文档同时说明按名称搜索不具备一对一唯一性；这个字段是宽幅 banner，不是逐集剧照，仍需真实 Bangumi↔AniList 稳定 ID 映射、授权/署名核查与图像抽查。详见 [AniList Media reference](https://docs.anilist.co/reference/object/media) 与 [Media search guide](https://docs.anilist.co/guide/graphql/queries/media)。
- TMDB 有 TV 搜索与系列图片（可返回 backdrop、poster、logo）的正式 API；本轮对 Re:Zero、Mushoku Tensei 与 Grand Blue 的 `/search/tv` 无凭证请求均返回 HTTP 401，响应为 `Invalid API key: You must be granted a valid key.`，所以本机无法确认这些系列的 TMDB match/backdrop 数量。继续该路径需要 TMDB API Read Access Token；官方流程见 [TV search](https://developer.themoviedb.org/reference/search-tv)、[TV series images](https://developer.themoviedb.org/reference/tv-series-images) 和 [application authentication](https://developer.themoviedb.org/docs/authentication-application)。

## 本轮实测

| 项目 | 结果 | 证据 |
| --- | --- | --- |
| 在线冷启动 | 「热门」为真实遥控焦点，节目加载后保持在热门；当前焦点封面返回 600×850 竖图，模糊铺底完成 | build/home-a-evidence-20260924/home-final.xml、home-final.png；HomeBackdrop 日志 |
| 慢网输入 | 临时 GPRS 限速与 1500ms 延迟下，首帧仍聚焦热门；目录加载时用户移动到「日常」，加载完成没有抢回焦点 | home-slow-before-input.xml、home-slow-after-input.xml、home-daily-slow.png |
| 离线冷启动 | 仅对 Kazumi 调试包短暂启用 Android 测试防火墙拦截；进程冷启动后仍显示热门焦点、错误信息与重试入口，没有崩溃；随后撤销规则 | home-offline.xml、home-offline.png；最终防火墙状态为关闭、应用网络允许 |
| 详情返回 | 第 3 张卡进入详情，返回恢复同一卡片焦点；不移动立即确认可再次打开同一详情 | home-focus-first-card.xml、home-detail.xml、home-focus-return.xml、home-detail-again.xml |
| 首页变动矩阵 | `home-ui-acceptance` 六项通过：热门冷启动焦点、空目录、详情打开期间删除焦点项目并回到最近剩余卡、慢分类迟到结果不覆盖、清缓存后刷新、离开首页取消简介请求 | home-ui-acceptance.txt；使用假目录与真实遥控方向键/确认键，不写播放进度或来源状态 |
| 进程回收 | 在「日常」第 10 张卡聚焦时通过系统 Home 离开并终止应用进程；重新启动后分类、视口和同一卡片焦点恢复 | home-before-process-kill.xml、home-after-process-kill.xml、home-after-process-kill.png |
| OLED 纯黑 | 首页开启后，画面背景成为纯黑，导航、标题与六列卡片仍可用；已关闭并重启回正常背景 | home-oled.png、home-restored.xml |
| 焦点/背景 reducer | 覆盖 A→B→C 迟到结果、A→B→A 代次、缺图/OLED 清空和重复资源键 | HomeBackdropStateTest.kt |
| 播放相关回归 | recent-watch-navigation、player-controls、episode-session、verification-layout、playback-recovery 均通过本地测试夹具；不等于真实在线播放或验证码实机通过 | 当轮 instrumentation 输出 |
| 进度与验证隔离 | 首页回归注入假目录，不进入播放器、来源选择或验证码页；播放/验证本地夹具仍通过。tv_settings、tv_library、search_history 三项相对启动检查点保持不变；没有生成真实观看记录或验证码会话 | home-ui-acceptance.txt、五项本地回归日志、user-data-verify 输出 `user_data_checkpoint_unchanged stores=3 label=home-a-20260924` |

慢网配置、应用防火墙规则与 OLED 开关均已恢复。没有连接或操作物理电视 192.168.123.217:5555，也没有操作 emulator-5560。工作区没有对这些设备做默认桌面更改。

## 构建结果

- 221 个 release 单元测试通过（`testReleaseUnitTest --rerun-tasks`）；Gradle 输出有 2 条既有 Android API 弃用警告（`TRIM_MEMORY_RUNNING_LOW`、`scaledDensity`）。
- 最终实现源码通过 `lintRelease`、`assembleDebug` 和 `assembleDebugAndroidTest`；本轮没有运行 release 打包。
- 最终 debug APK：15,376,744 字节，SHA-256 `D1F0C32B2CED9D1A591DC49F4A2F362324CCB6BC044EE8D729603971063A3F89`。
- 最终 AVD 截图和 XML 位于本机忽略目录 build/home-a-evidence-20260924/，不纳入 Git。

## 尚未关闭

- 全屏背景排版已经落地，但目前仍用竖版封面制作柔化氛围层。AniList 有 3 个热门样本的可用宽幅 banner，却不是逐集剧照；Bangumi↔AniList 稳定 ID 匹配和图像使用条款尚未确认。TMDB 的正式授权 API 支持 series backdrops，但本轮无访问令牌，搜索请求实际返回 401。场景剧照接入仍待解决这两个外部闸门。
- 没有在目标实体电视上测文字可读性、裁切、内存峰值、焦点帧率和长时间快速切换。
- 首页的空目录/删除回焦、快速连续切换、清缓存刷新和退页取消简介请求已在独立 AVD 的假目录仪器测试通过。还没有覆盖全部网络、尺寸、分类及电视固件组合。播放进度与验证码仅做数据不变性和本地夹具隔离检查；没有真实在线媒体、验证码服务或实体电视证明。
- Android 系统 DreamService 屏保、Android TV Preview/Watch Next 频道与 ROLE_HOME 默认桌面均未接入或启用。它们可分别借鉴沉浸图像、内容卡片与启动器布局；正式进入这些阶段前要在目标固件验证系统选择、频道批准/显示、退出恢复与默认桌面切换。普通应用入口仍保留。

系统边界以官方资料为准：[DreamService](https://developer.android.com/reference/android/service/dreams/DreamService)、[Android TV home-screen channels](https://developer.android.com/training/tv/discovery/recommendations-channel)、[ROLE_HOME](https://developer.android.com/reference/android/app/role/RoleManager#ROLE_HOME)。Android TV 主屏默认频道与用户批准的其他频道行为不同；这些 API 不保证各厂商桌面以相同方式呈现频道或提供默认桌面选择。没有在任何设备上启用 Kazumi 作为系统屏保、频道提供方或默认桌面。

没有提交、推送或发布安装包。
