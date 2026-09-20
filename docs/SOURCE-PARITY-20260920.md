# 来源执行能力对照（2026-09-20）

此文是源码审查，不是逐源播放验收结果。以本轮修复前代码为基线；后续已修项须补测试证据后更新状态。

## 固定版本与范围

- Kazumi 上游：`285fa01b55f88d268e6fbfe69db704b18ff3ed5f`。本日通过 `git ls-remote` 核对并 fetch；不是继续把旧的 `1b395a50` 当作最新版。解析、规则、验证目录在这两个版本之间没有变化，视频 UI 有重构。
- KazumiRules：`0d85fc80ab6c208548d9ee9c9e81271b08ff7f39`，仅 `index.json` 中 **17 个当前入口**是本轮完整清单；仓库其他 JSON 是未列入当前目录的规则，不应全部当作仍维护的来源导入。
- 原生审查位置：`SourceRule.kt`、`RuleRepository.kt`、`XPathRuleEngine.kt`、`ApiRuleEngine.kt`、`WebMediaResolver.kt`、`LegacyMediaAddress.kt`。

## 共性差异：按处理优先级排序

| 能力 | 上游行为 | 原生基线 | 处理与验收 |
|---|---|---|---|
| XPath 相对节点上下文 | `node.queryXPath` / `roadNode.queryXPath` | 把单个节点克隆成新文档，兄弟节点被丢弃 | **P0**：ezdmw 明确使用 `/self::*/following-sibling::a`，当前必然失去剧集节点；实现匹配上游语义的上下文，增加兄弟轴、union、`//`、`.//` 组合夹具，避免修一个源破坏全部传统规则 |
| 裸 `//` 选择器 | 当前 aafun 规则使用 `chapterRoads: //`；标准 JAXP 不接受 | 直接交给 JAXP，可能立即报无效 XPath | **P0**：先用上游 XPath 实现/夹具核实简写语义，再归一化；不可任意替换成整站所有节点 |
| 默认 UA 与验证会话 | HTTP/WebView 使用浏览器 UA；验证后保存 verified UA，后续请求优先使用它 | 17 条规则的 UA 全为空，默认值是 `Mozilla/5.0 KazumiTV/0.1`，虽然各阶段一致，但非完整浏览器 UA | **P0**：默认采用兼容浏览器 UA，明确同一验证会话保持一致。不要逐请求随机换 UA，也不要将 UA 修复等同于所有 403 已解决 |
| Referer | 搜索/详情 executor 默认 baseUrl + `/`，API 请求头可覆盖；播放器仅在规则非空时设置规则 Referer | SourceRule 将空 Referer 补成 baseUrl；解析候选有时改成页面/iframe URL；媒体拦截保留请求 Referer/Origin | **P1**：明确网页请求和媒体请求两个语义，规则显式覆盖与捕获请求上下文优先级需一致；空值不能简单当作显式设置 |
| Cookie 与完成验证后的请求 | 使用来源 cookie 管理及 verified UA；GET XPath 可直接解析验证后收获的页面，失败才重新请求 | WebView CookieJar 共用；验证成功后重发原请求；没有收获页面直接解析路径 | **P1**：验证后再次挑战的站点可借鉴收获 HTML 路径，仅限匹配原请求的 GET XPath 页面，不能拿 GET 页面替代 POST/API 响应 |
| HLS 广告过滤 `adBlocker` | 传入 media-kit `PlayerConfiguration(adBlocker: ...)`；下载也有过滤路径 | 字段保留但未传到 Media3/manifest 处理，实际未执行 | **P1/单独适配**：当前 5 源启用。需查上游 media-kit 具体实现后适配 Media3；不能粗暴删除所有 DISCONTINUITY（合法时间线也用它） |
| 提前注入与旧内核分支 | Android 检测 `DOCUMENT_START_SCRIPT` 后选择现代/兼容实现 | 基线主要页面加载后注入和请求拦截 | **P1**：能力检测、早期 hook、旧内核回归；网站自身新 JS 不兼容不能仅靠换注入时机解决 |
| `useLegacyParser` / iframe 参数 | 观察 iframe，`decodeVideoSource` 从查询参数提取媒体 URL | 已有 `LegacyMediaAddress` 与 iframe 分支；需核对多重编码和动态 iframe 行为 | xfdmneo 必须专项回归；不是全部遗漏。验证嵌套编码、签名参数不被破坏、无媒体参数时不误判 |
| URL 归一化 | 同站协议按规则统一、去除尾斜杠/空 query，用于稳定剧集身份 | 基本 URI.resolve；身份归一化不等价 | **P2**：主要影响历史/选集身份；移植时避免改坏实际端点，保留跨站协议及端口差异 |
| API 模式 | GET/POST、query/header/body 模板、受限 JSONPath、nested/delimited、episodePage | 已有对应执行能力；当前 sorani 路径用到的字段均有实现 | 用相同 JSON 夹具对照；无证据时不另写站点搜索引擎 |
| `useWebview` / `useNativePlayer` | 上游 Plugin 注释明确是保留导入导出的 **legacy schema** 字段 | 未据此切换播放模式 | **不是已证实的功能缺口**；17 源二者全部 true。不要为了兼容旧字段再造网页播放器 |
| `muliSources` | 搜索上游使用位置仅声明/编辑/序列化，章节解析并不按它裁切线路 | 不据此裁切道路 | 当前无执行差异证据；sorani=false 不能作为只验收一条线路的理由 |

## 17 个来源配置覆盖表

“已实现”仅代表字段有执行路径，真实网站结果另见逐源审计。默认 UA 差异影响全部 17 源。

| 来源 | 当前配置特点 | 执行覆盖 / 重点缺口 |
|---|---|---|
| 7sefun | XPath、默认现代解析 | 基本 XPath/解析已实现；网络及页面变化需实测 |
| aafun | XPath、chapterRoads=`//` | 裸选择器语义需对照；不能因为同域 moonci 能播就算此规则通过 |
| AGE | XPath、默认现代解析 | 字段已实现；逐源实测 |
| akianime | XPath、class 选择器 | 字段已实现；逐源实测 |
| baimao | XPath、adBlocker=true | XPath 已实现；HLS 过滤遗漏 |
| dalvdm | XPath、图片验证码 | 验证字段已有路径；人工输入后恢复原请求需实际验证 |
| DM84 | XPath、adBlocker=true | XPath 已实现；HLS 过滤遗漏 |
| ezdmw | XPath、显式 Referer、兄弟轴 union | **节点上下文确定性缺口**；必须修复/回归 |
| giriGiriLove | XPath、图片验证码 | 验证字段已有路径；实际验证与续请求待逐源记录 |
| gugu3 | XPath、adBlocker=true | XPath 已实现；HLS 过滤遗漏；无对应集数不等于源失效 |
| LMM | XPath、文字检测+自动按钮验证、显式 Referer | type2 有实现；检查真实挑战成功判定及 Cookie/UA |
| mgnacg | XPath、图片验证码 | 验证字段已有路径；实测 |
| moonci | XPath、`.//` 相对选择器 | 字段已实现；不同线路分别报告 |
| mutefun | XPath、图片验证码 | 上次已有真实人工验证成功记录；本轮仍需复测 |
| MXdm | XPath、adBlocker=true | XPath 已实现；HLS 过滤遗漏 |
| sorani | API nested、query 模板、episodePage、adBlocker=true | 规则字段已有执行；原生专用媒体 API 是旧 WebView 补充；HLS 过滤遗漏 |
| xfdmneo | XPath、useLegacyParser=true | legacy 分支已有；动态 iframe / 查询参数专项回归 |

## 固定版本源码依据

- [规则字段及 legacy 注释](https://github.com/Predidit/Kazumi/blob/285fa01b55f88d268e6fbfe69db704b18ff3ed5f/lib/plugins/plugins.dart)
- [XPath 上下文与 GET/POST](https://github.com/Predidit/Kazumi/blob/285fa01b55f88d268e6fbfe69db704b18ff3ed5f/lib/services/plugin/xpath_rule_strategy.dart)
- [请求上下文、验证 UA、验证页面复用](https://github.com/Predidit/Kazumi/blob/285fa01b55f88d268e6fbfe69db704b18ff3ed5f/lib/services/plugin/rule_engine.dart)
- [API 模板与 JSONPath](https://github.com/Predidit/Kazumi/blob/285fa01b55f88d268e6fbfe69db704b18ff3ed5f/lib/services/plugin/api_rule_strategy.dart)
- [HTTP 默认 UA](https://github.com/Predidit/Kazumi/blob/285fa01b55f88d268e6fbfe69db704b18ff3ed5f/lib/request/clients/plugin_site_client.dart)
- [播放器请求头与过滤设置](https://github.com/Predidit/Kazumi/blob/285fa01b55f88d268e6fbfe69db704b18ff3ed5f/lib/pages/video/video_controller.dart)
- [过滤配置传给 media-kit](https://github.com/Predidit/Kazumi/blob/285fa01b55f88d268e6fbfe69db704b18ff3ed5f/lib/pages/player/controller/player_playback_controller.dart)
- [WebView 平台能力选择](https://github.com/Predidit/Kazumi/blob/285fa01b55f88d268e6fbfe69db704b18ff3ed5f/lib/webview/video/video_webview_controller.dart)
- [iframe 媒体地址处理](https://github.com/Predidit/Kazumi/blob/285fa01b55f88d268e6fbfe69db704b18ff3ed5f/lib/utils/media.dart)
- [当前规则目录](https://github.com/Predidit/KazumiRules/blob/0d85fc80ab6c208548d9ee9c9e81271b08ff7f39/index.json)

建议先完成 XPath 上下文和默认 UA 两个共性修复，再用同批来源复测差异；网络不可达、规则空结果、媒体失败必须分别归类。此源码审查没有进行设备操作或构建；随后获主任务授权实施以下定点修复。


## 本轮定点修复进展

已修改 `XPathRuleEngine.kt` 并新增 `SourceXPathParityTest.kt`，构建和真机验证由主任务统一执行，本文不预先标记通过。

- ezdmw：不再克隆孤立节点；保留 DOM 父节点和兄弟节点，并把独立绝对路径改为以当前节点为起点的路径。已有 `//`、`.//`、括号 union 仍限制在当前结果上下文，字符串里的斜杠/竖线不重写。
- aafun：仅将精确的裸 `//` 映射为当前根节点。这是上游解析器的实际语义，不是猜测：锁定依赖 `xpath_selector 3.0.2` 的 `lib/src/reg.dart` 中 xpathGroup 对裸 `//` 不产生步骤，`parser.dart` 产生空 selectorList，`execute.dart` 从 `[element]` 开始且空列表直接返回它。
- 兄弟节点证据：锁定依赖 `xpath_selector_html_parser 3.0.1` 的 `lib/src/model.dart`中 HtmlNodeTree 的 parent/nextSibling 使用原始 node.parentNode/nextElementSibling。上游没有把行克隆脱离文档。
- 包版本及内容校验值可由 [上游 pubspec.lock](https://github.com/Predidit/Kazumi/blob/285fa01b55f88d268e6fbfe69db704b18ff3ed5f/pubspec.lock) 核对；本机读取的是 Pub 缓存中的上述版本，不是最新分支猜测。
- 4 个新增测试覆盖实际 ezdmw 四分支表达式、裸 `//` 只返回一个线路根、跨行 union 隔离、字符串字面量保留。


## HLS 广告过滤：已追到实际底层补丁

### 锁定的执行链

1. Kazumi `285fa01b` 的 pubspec.lock 固定 `Predidit/media-kit@78d4cce7b49d5b6b918f78b18ec1fbb7c400b9da`。
2. [media-kit real.dart](https://github.com/Predidit/media-kit/blob/78d4cce7b49d5b6b918f78b18ec1fbb7c400b9da/media_kit/lib/src/player/native/player/real.dart) 将开关转成 `demuxer-lavf-o` 中的 `hls_ad_filter=1`。这不是 mpv 画面滤镜，也不是 Flutter 对播放清单删行。
3. 同一提交的 [Android build.gradle](https://github.com/Predidit/media-kit/blob/78d4cce7b49d5b6b918f78b18ec1fbb7c400b9da/libs/android/media_kit_libs_android_video/android/build.gradle) 引用 libmpv Android `v1.2.7`。该 tag 本次解析到 `dd2bfba8209bcd22e2d4c79f125b40e619e637ed`。
4. [实际 FFmpeg 补丁](https://github.com/Predidit/libmpv-android-video-build/blob/dd2bfba8209bcd22e2d4c79f125b40e619e637ed/buildscripts/patches/ffmpeg/ffmpeg-hls-kazumi-combined.patch) 修改 `libavformat/hls.c`；[依赖信息](https://github.com/Predidit/libmpv-android-video-build/blob/dd2bfba8209bcd22e2d4c79f125b40e619e637ed/buildscripts/include/depinfo.sh) 固定 FFmpeg 7.1.3 / `f46e514491172d15bd74b4abb1814cd2f05a763e`。

### 播放过滤实际算法与边界

- 只有配置启用且清单出现 DISCONTINUITY 才启动检测。
- 视频包原始 PTS 相对之前主内容 PTS 后退超过 1 秒，进入丢包状态。
- 丢包期间，PTS 回到广告前位置的 -2 秒至 +10 秒范围，认为主内容恢复；分别等到视频和音频恢复后调整 PTS/DTS offset，让输出时间线连续。
- seek 重置广告状态，避免把快进当成广告。
- 补丁记录了 segment.after_discontinuity，但播放包检测没有使用这个字段进一步约束触发点；标记存在后，检测是全局启用的。
- 因而此实现仍是启发式：合法时间戳重置、单轨内容、跨流 PTS 差异、缺失 PTS 等需要专门验证，不能宣称“原版保证不会误删”。以上风险来自代码推断，不是本轮真实来源复现结果。

下载模块的 [M3u8AdFilter](https://github.com/Predidit/Kazumi/blob/285fa01b55f88d268e6fbfe69db704b18ff3ed5f/lib/utils/m3u8_ad_filter.dart) **不是相同算法**：按 discontinuity 分组，把最长组当主内容，删除小于最长组 30%、首尾小于 30 秒、或小于 10 秒的其他组。片头、片尾、短章也可能满足这些条件。不能为了原生播放补齐字段就直接搬这套删组逻辑。

### 原生 Media3 的可行适配与必要验证

- 可以直接复用的概念：规则开关、默认关闭/来源显式启用、取消/seek 时重置状态、保留原流回退、记录过滤前后位置映射。
- **不应直接移植**：删除所有 discontinuity；仅按组长短判断广告；把已由 Media3 TimestampAdjuster 归一化的播放时间当作原始包 PTS。
- 若要接近上游效果，需要在 HLS 原始分片/提取器层采集未校正的音视频时间戳，并跨分片判断；这是新的底层适配，不是给 Media3 设置一个现成布尔选项。
- 更保守方案：先只分析完整 VOD（ENDLIST），保留全部分片；将疑似广告段收集为诊断。只有可确认的两侧主内容连续、两轨一致、边界匹配且过滤比例受限的片段，才考虑可回退地跳过。无法确认时原样播放。这个方案未实现，且不会覆盖所有上游能过滤的流。
- 如果将来重写播放清单，必须正确保留媒体序号、隐式 AES IV 与 KEY 轮换、MAP/init 段、BYTERANGE 偏移、DISCONTINUITY-SEQUENCE、合法时间戳边界及音轨对应。不能只过滤 URI 列表再沿用原 sequence。
- 验收至少包含：正常多段时间戳重置不删、广告插入后主内容恢复、只有音频/只有视频、B 帧重排、AES 隐式 IV、fMP4 MAP、字幕/独立音轨、seek 前后、取消与重试、短片、无 ENDLIST 的流原样保留。真机比较关闭/开启后的片段内容、音画同步、总时长和续播位置。

同一 FFmpeg 补丁还包含**独立于广告过滤的播放兼容修复**：PNG/GIF 伪装分片以不同 offset 且无误导文件名重新探测真实载荷；非标准扩展名/MIME 的 HLS 降低探测分数但不直接拒绝。这两项应单独评估 Media3 的真实表现，不能误归因为广告开关，也不能见到图片头就无条件强制当 TS。

### 许可边界（源码事实）

- media-kit 仓库 LICENSE 为 MIT，复制相应代码保留通知。
- libmpv 构建仓库 LICENSE 对 default/full 脚本标 MIT、encoders-gpl 标 GPLv3+；这不覆盖所有构建产物依赖的许可证。
- 被修改的 FFmpeg [hls.c 原始头部](https://github.com/FFmpeg/FFmpeg/blob/f46e514491172d15bd74b4abb1814cd2f05a763e/libavformat/hls.c) 为 LGPL-2.1-or-later；不得因为构建脚本是 MIT 就把 FFmpeg 衍生实现标成 MIT。若纳入二进制，还需遵循实际链接和构建组件许可。
- Kazumi 项目为 GPLv3。若移植其 Dart 下载算法，应保留项目许可与归属；但该算法本身并不适合作为可靠播放修复的直接替代。

本节只作调查与方案，未引入 FFmpeg、未修改原生播放管线或广告设置。

## 实际页面检查补充（2026-09-20）

主任务从应用网络抓取的 `source-page-diagnostic-*` 页面仅作为数据读取，未在宿主机执行脚本。以下区别于源码推断：

| 来源 | 实际页面证据 | 分类与下一步 |
|---|---|---|
| giriGiriLove | HTTP200、普通站点标题，但 body 明确包含验证码 input、`img.ds-verify-img`、提交按钮；规则无独立 detectValue | **通用检测遗漏**：恢复上游 captchaImage/captchaButton 回退检查；不是“没有节目” |
| mgnacg | HTTP200、标题“搜索-橘子动漫”、正文要求验证码、相同图片 class | 同一检测遗漏；后续人工提交还需确认规则的位置型 input/button XPath 是否仍有效 |
| xfdmneo | 搜索请求被重定向到 XIFAN 综合门户，内容是动漫/漫画/游戏入口，没有旧站搜索列表 | **上游规则/域名迁移**：当前规则不能得到搜索结果；不能靠放宽 XPath 把门户链接伪装成节目。需核对新旧站实际搜索/剧集结构后提出版本化规则更新 |
| LMM | HTTP200 729字节，标题身份验证，body 没有按钮；依赖 jquery、md5、`/template/jable/statics/js/search.js` 生成界面 | 识别挑战已正确；按钮不存在于静态 HTML 不能直接判规则坏。宿主两次仅取公开 search.js 都HTTP403（含浏览器UA/Referer），已保存抓取时间与状态；**不等于已证明电视相同403**，需应用内子资源状态才能定位 |
| baimao | 第12集页面有一个 `iframe#hm_playfram`，但 src 为空，inline 调用 `setPlayFrm`；已发布的 pck.js 是混淆脚本 | 需要网页执行后动态 iframe/媒体请求诊断；静态 iframe count=1 不代表拿到了播放器地址。没有源码依据可写一个固定媒体 URL 模板 |
| akianime | 选中第三季实际只有7/8集，因此诊断选01；MacCMS metadata 的 url 是 Doki opaque identifier，不是媒体 URL | metadata返回0是正确筛选；站点 playerconfig 的 YDY ps=1 指向解析器，player.js 切到 parse player 创建网页解析路径。需检查解析器页面加载/媒体捕获，不能把 Doki 值塞给原生播放器 |

已实施的定点修复：`SourcePageChecks.kt` 在 enabled 且 detectValue 为空时，按上游检查已配置 captchaImage/captchaButton。新增 `SourceChallengeFallbackTest.kt` 共5项测试，验证普通标题的真实形状挑战、按钮挑战、正常页面/禁用负例、显式检测优先和无效XPath明确失败。构建/设备结果由主任务填写。

上述静态脚本保存在本地忽略的诊断目录。baimao 混淆脚本未执行，也未据其未经验证的字符串生成站点专用补丁。没有修改固定上游规则或电视自定义规则。

## 旧 WebView 媒体发现补充

本轮核对上游 `lib/webview/video/impl/video_webview_impl.dart` 的 `shouldInterceptRequest` / `_isRangeVideoRequest`：旧实现会把带 `Range: bytes=...` 的非网页资源列为媒体候选，即便没有媒体扩展名。原生此前仅按扩展名拦截；旧内核又不能注入跨域 iframe，因此确有漏掉无扩展名媒体请求的通用路径。

已补 `WebMediaResolver` 的 Range 候选入口（排除脚本、样式、页面、JSON、图片和字体路径），所有候选仍须通过现有 HTTP/内容探测。增加旧提供程序 `onPageStarted` 的尽早注入，保留轮询补装；这不是承诺与 document-start 等价。动态快照只记录有效非空 iframe 数、不可访问子框架数及媒体候选数。

同时纠正错误归因：网页或统计脚本的 SyntaxError 只作诊断，不再单独决定最终“脚本不兼容”错误；失败仍按实际媒体探测/加载/未发现阶段报告。没有把统计脚本错误当成 baimao 所有线路失败的证据。

新增 `MediaRangeDiscoveryTest` 4项候选政策测试。仍需主任务运行：旧内核跨域 iframe 的无扩展名 Range 视频、普通 JS Range负例、空 iframe 后续赋值、取消释放，然后复测 baimao 已在现代内核成功的相同道路。源码修复本身不是这些设备用例的通过证据。

## 播放请求头统一（本轮实现，待主任务回归）

上游 VideoPageController 在创建 PlaybackInitParams 时显式传入非空 `currentPlugin.referer`，此值是最终原生播放器头；原生之前的 metadata、API、WebView 候选路径分别覆盖为页面或 iframe URL，可能悄悄忽略规则覆盖。

新增 `MediaRequestHeaders.forMedia` 并统一用于 WebMediaResolver 的直链、页面 metadata、API结果与浏览器候选：非空规则原始 referer 优先；规则缺省/空值则保留捕获的 iframe Referer，未捕获时使用实际页面（metadata使用重定向后页面）。**SourceRule.referer 自动补的 baseURL 不当作显式覆盖**。Origin保留实际捕获值，UA统一沿用规则/当前会话使用值。只有这三个头进入播放请求；Cookie仍由AppHttp按目标地址挑选，不把源站Cookie复制给媒体站，也不复制Authorization或Range。

这里显式规则优先是上游行为；缺省时保留实际iframe上下文是原生已有兼容能力，未为了机械对齐上游而删除。4项新增单测覆盖显式覆盖、空值保留iframe、metadata重定向及稳定UA、Cookie/其他头不复制。

## giri 验证页面后续根因：限频提示

主任务保存的 `giri-live.private.html` 与较早 HTTP 验证页不同：当前是 `.msg-jump` 系统提示，正文“親愛的：請不要頻繁操作，搜索時間間隔爲3秒前”，没有验证码。HTTP检测后立即打开WebView触发了站点搜索间隔，并非隐藏模板或JS不兼容。

新增严格限频识别：仅匹配该类系统提示容器、精确简繁标题和锚定的搜索间隔消息，返回固定安全异常 `SourceRateLimited`。验证脚本返回 `throttled` 标志供UI提示稍后重新加载；验证成功状态机明确排除限频页面。没有增加无限重试、统一全站等待或域名硬编码。新增4项正负/状态机测试，运行由主任务统一完成。

## 严格限频后的有界重试

在上节已确认的限频响应基础上，SourceRateLimited现携带提示中严格解析的等待毫秒数。RuleRepository同一页面请求（包括自动验证后恢复）共享一个限频重试预算：只在明确限频且要求等待1–10秒时取消友好地等待该时长加250毫秒，再重发原始URL/方法/头/body一次；第二次限频或超出上限直接保留固定错误。

同一来源origin的已知冷却窗口共享协调，正常响应、真实空结果、普通HTTP失败和验证码不建立等待。没有固定全站sleep，没有无限重试，也没有声称解决首次HTTP检测后立即打开验证WebView的导航限频；后者仍由验证UI明确提示。5项策略测试覆盖一次重试、同源已知窗口、不同源不等待、异常/过长限制不重试、跨验证预算及取消不再发送请求；等待秒数解析另有断言。构建和实测由主任务统一完成。


## 2026-09-21：headless viewport 与跨域 iframe 修复已验证

这次是明确的原生遗漏：`WebMediaResolver` 和 `AutomaticVerification` 原先创建未挂载的 WebView 后直接加载页面，没有父布局，也没有 `measure/layout`；响应式 iframe 的百分比尺寸因而缺少实际 viewport。此前受控用例把 iframe 写死为 640×360，掩盖了缺口。上游旧实现创建有明确尺寸的 headless WebView。现在两条原生路径共用 `HeadlessWebViewport`，加载前按设备显示尺寸测量与布局，保留可见播放器容器的尺寸门槛；真机诊断尺寸为 1920×1080。

同时补齐有界 iframe 发现：仅兼容路径提升跨域播放器 iframe，最多三页、两层，不扩大总时限；第一候选页 404/连接失败只使该候选失败，允许下一候选，源站顶层失败和 renderer crash 仍终止。到达 frameWait 后，提升待尝试 iframe 优先于下一投机探测。ResourceTiming 的无类型 XHR 不再填充明确媒体队列：投机最多八项，明确媒体最多二十四项，明确候选优先；投机返回 JSON/HTML/400 不覆盖最终媒体错误。

实际受控回归文件 `artifacts/source-audit-20260920/web-discovery-tv-preview.txt` 与 `web-discovery-modern-preview.txt` 均 PASS：响应式 100% iframe、首帧 404 后第二帧成功、40 次普通 JSON XHR 后延迟媒体仍被发现、要求非零 viewport 的自动验证按钮、跨域 extensionless Range、动态 iframe、脚本 Range 排除。现代内核另通过 document-start 早期 XHR/跨域发现；旧电视明确 SKIP 不支持的 document-start，不能写成通过。

真实源证据 `ezdmw-tv-preview.txt` 已完整落盘：无职转生第三季第12集，线路1、2（日志 road=0/1）均显示 viewport → iframe_fallback → HLS 解析 → 首帧、播放推进、seek、pause/resume 全部通过。线路3仍为媒体探测失败，未标成全源通过。此前同电视 `ezdmw-tv-timing.txt` 没有触发 iframe_fallback。结合缺失布局代码、百分比尺寸受控回归及真机恢复，可确认 viewport/iframe 路径是实际修复，不能再把这两条线路全归为“旧 WebView 不支持站点 JS”。这是短播验收，尚非两条线路整集验收，也不证明 LMM 原先后台验证失败只有这一原因。

### baimao 脚本兼容性仍需最小定位证据

已只读检查保存的 `source-page-diagnostic-baimao-1789918016663`：`static-pck.js` 主体在第1行、`static-hm_pck.js` 第8行是普通正则匹配，未发现可直接证明旧66不能解析的 optional chaining / nullish coalescing。pck 中确有箭头函数和 const，但仅这些不能证明旧66不兼容；正则扫到的 `#ipchk_getplay` 是字符串选择器，不是私有字段。混淆字符串或运行时另加载脚本仍不能仅凭本地静态页排除。

现有安全日志只有 SyntaxError 的 host+line，无法将“line=8”对应到具体脚本；因此没有证据将该错误归到播放器关键脚本，更不能据此重写源。最小补证为：单次失败道路的 console sourceId/行/列/错误种类保存在私有诊断文件（公开日志只稳定哈希）；同次实际响应脚本的字节、字符集、HTTP状态与哈希；错误前后 iframe src 是否发生更新、`typeof setPlayFrm`、主文档与子帧加载阶段。保存数据不得执行混淆代码，也不得把签名 URL/Cookie/完整错误文本发布。先与现代同道路的脚本哈希/阶段对齐，再判断语法、网络、UA分流或 iframe 状态差异。


### baimao 私有 console 补证（随后已定位）

后续 `console-private/console-baimao-baimao-console-final-road0-*.jsonl` 与 road1 记录把失败定位到实际 Artplayer bundle 第8行 `Unexpected token .`，随后 iframe 页面第29行 `Artplayer is not defined`。按私有 sourceId 获取的 `artplayer-bundle.private.js` 为 HTTP200 / 157070字节，SHA256 `d44b79ad36132f6dff970212dcf03d5e616450b546dcab8902970fc374224bab`；用应用相同UA重取字节完全相同。第8行包含17处 optional chaining (`?.`) 与2处 nullish coalescing (`??`)；这次是播放器关键 bundle 的具体语法兼容失败，而非统计脚本猜测。

对应 `artplayer-frame.private.html` 第25–31行直接取 `new URLSearchParams(location.search).get('url')` 并赋给 `new Artplayer({url:q_url})`。捕获的 iframe 查询值是合法 HTTP .m3u8 地址，现有 `LegacyMediaAddress.extract` 已能作纯数据解码，不需要执行脚本或替换 Artplayer。最小兼容补充是对已识别播放器 iframe 的明确媒体参数运行同样的安全提取，再走现有媒体 HTTP/content probe 与请求头策略；不能直接把 query 中任何 URL 都当媒体。原始 sourceId、媒体URL与页面保存在忽略的私有 artifacts，没有写入文档或公开日志。


该补充已落代码：明确 playerLike 的同源/跨域 iframe 均可提取其查询中的 HTTP 媒体地址，不依赖 legacy 标志；原显式 legacy 路径保留。提取后仍强制媒体探测，使用统一 Referer/Cookie 政策。新增受控 fixture 同时放置携带有效媒体参数的 1px 广告和响应式播放器，两者脚本故意语法失败，断言只接受播放器参数且保留 iframe Referer。此新增用例待主任务统一设备回归，未把编写测试当作通过。
