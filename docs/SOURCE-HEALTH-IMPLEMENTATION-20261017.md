# 源健康与首次选源（issue #19）

状态：已完成集成；API 36 模拟器 feature 20505 与 Android 9 电视 feature 20507 的受控 fixture 首帧/有限选源已验证，电视健康记录与取消也已验证。真实站点独立补证据见下节，不把受控 fixture 结论推广为全站可用。最新全量验证 head `606593f1373002860b72eb7d2309f02a859c7433` 为 955 项通过；`801b31e7` 为后续文档状态，未冒充重跑。统一状态及设备证据以 [PROJECT-STATUS.md](PROJECT-STATUS.md) 为准。

## 实现与边界

- 详情页「源健康」是显式入口，只使用已加载规则和当前番剧名称/别名。唯一严格标题匹配才继续，不默认取第一条搜索命中。
- 串行，最多 12 条规则、总请求预算 180 秒，每条 35 秒；取消与迟到结果隔离。每个候选结束先释放解析器/播放器，4 秒内无法确认释放则停止，不开始下一候选。
- 首次无历史时保留开关：先用单剧手动选源记忆；无记忆时按当前剧有效首帧记录、其他剧有效首帧先验、未测规则排序，最多 3 条/75 秒。仍重新检索真实目标。历史恢复和明确手选优先。
- 独立可见静音探测播放器，不写观看历史、收藏、规则，不开第三方中转。正式播放与探测分开；二次解析可能失败，现有播放错误/手动换源入口仍适用。
- 本地 schema v1，最多 128 条健康元信息；24 小时过期、规则 SHA-256 指纹或应用/设备/解码配置变化后失效。记录番剧、规则版本、首路第 1 集序号、时间、分层结果和固定失败分类。不保存媒体 URL、页面内容、cookie、header、异常原文。
- 另存最多 128 条单剧手动源偏好，仅规则名和指纹，不保存地址；规则变化后失效。健康页可清除健康记录并控制首次自动选源。

## 已发现的验收风险

冻结 media-kit 源码 android_video_controller/real.dart 在视频尺寸监听第 125 行就完成 waitUntilFirstFrameRenderedCompleter；第 282 行也可由 native Notify 完成。因此 Android 上该 Future 不是独立的真实画面首帧证据。必须采用明确分层，不能把尺寸/播放器启动标成真实首帧。该问题已由固定依赖的本地 vendor 修复：使用 SurfaceTexture 实际 frame-consumed 通知，并移除 videoParams 假首帧完成。修复已经集成，并在上述模拟器与电视受控 fixture 验收到 firstFrameNotify；旧的尺寸回调不能作为首帧证据。

## 可执行验收清单

- 单元/控件：唯一匹配、相似续作拒绝、低并发和数量预算、总/单条超时、验证码不进入播放器、取消后迟到结果不写入、释放完成先于下条、过期/规则/环境变化、损坏和新版本缓存、128 条上限、单剧偏好失效、Back/取消焦点返回。
- 模拟器：详情遥控入口和开关；0/1/多规则；长列表滚动；慢搜索、解析失败、已解析但黑屏、解码失败、取消与返回；进程退出后无探测服务或播放器残留。
- 电视 Android 9：同一包/提交/配置核对；至少一个真实画面首帧/声画观测与一个失败源；取消时原收藏/规则/历史保持；手动偏好和历史优先；首次候选失败清晰回手动；不同作品重新匹配；弱网/验证码不重试风暴。
- 不使用此检测结果宣称全站可用、所有集可用、外部音轨/字幕或完整长时播放已通过。

源健康子工作线早期 gh issue 只读请求遇到代理 socket 权限限制；集成负责人随后实时读取 issue #19。下列早期定向证据只描述该阶段，后续集成构建与设备验收已在项目状态记录；不将子工作线当时未操作设备写作当前全项目未验。

## 2026-10-17 本地证据

- `flutter test --no-pub test/source_health_test.dart test/source_health_page_test.dart test/tv_detail_actions_test.dart`：27 项全部通过（14 服务、4 健康页面/偏好、9 既有 TV 详情）。包括空搜索列表、自动成功返回匹配候选、Back/取消、取消后无悬空定时器。
- changed-files `dart analyze`：No issues found（0 error / warning / info）。`git diff --check` 通过。
- `flutter pub get --offline` 已从缓存完成依赖解析；之后 Windows 插件 symlink 检查退出 1（开发者模式未启用）。没有更改系统设置；生成的 package_config 支持上述 --no-pub 测试。
- 这组早期本地测试本身不包含设备与网络媒体证据；后续原生修复和设备受控 fixture 验收已完成，见本页当前状态和项目状态链接。

## 模拟器探测配置差异修复

集成模拟器 QA 出现无响应后，核对发现健康页只选择 `vo=gpu`，没有同步生产播放路径对自动 TV 模拟器的 `hardwareAcceleration=false / hwdec=no` 策略。现抽取 `resolveAndroidVideoConfiguration`，正式播放与健康探测共用完整配置；显式 GPU/GPU-next 和用户解码开关保持，direct MediaCodec 约束、既有恢复逻辑保持。该差异已修复，但不能据此断言无响应根因已经定位或问题已消失。日志 `feature-health-anr.log` 中可见 SurfaceTexture/640×360 尺寸事件，仍不足以证明真实首帧或 ANR 因果。

验证：Android output + source health service/page + playback recovery 共 51 项通过；涉及文件静态检查 0 error / 0 warning，生产播放器既有 3 条花括号 info 未改。该子工作线定向修复阶段没有构建或设备操作；后续集成负责人已完成 feature 20505 / 20507 首帧与有限候选复测，旧 ANR 原证据仍保留，不能据后续成功倒推根因。


## 2026-10-17 真实公开站点的主机分层补证据

用户已授权选择已有公开测试番剧进行低并发探测。复用 2026-10-15 公开验收中的 **giriGiriLove 2.5 / API 9** 与 **Fate/stay night Unlimited Blade Works**；明确区别于 Fate/stay night 2006，禁止沿用旧元数据误认为同一作品。

- 官方公开规则读取 1 次，规则文件 SHA-256 `4d7b4a32c68fcbf27ac1b2dd719408dd960067e5c40599ba90a33c05e2a8e01b`，搜索模式 API、章节模式 XPath。没有修改已加载规则或用户设置。
- 2026-10-17 12:08:46 UTC 开始，**站点请求恰好 3 次**，并发 1、重试 0、单次 15 秒上限、总请求预算 45 秒。使用普通无凭据 HTTP；未用登录、cookie 或验证码绕过；媒体请求 0。
- 搜索 `Fate`：HTTP 200，1.407 秒，5 条结果。唯一明确 UBW 条目是「命运之夜 无限剑制 Fate/stay night [Unlimited Blade Works]」，另有独立的「命运之夜 Fate/stay night 2006」条目。
- UBW 章节页：HTTP 200，0.984 秒，按该规则 `chapterRoads` / `chapterResult` 的 XPath 读到 **1 条线路、27 集**。
- 首路第 1 集页面：HTTP 200，1.016 秒。静态页面无直接 video/iframe 标签；**未运行应用 WebView 媒体解析，未运行播放器首帧验证**。主机 Python/lxml 的解析只证明当前规则表达式匹配本次公开响应，不能替代应用 RuleEngine/WebView 的设备端验收。

证据保存在本地任务产物 [host-probe-result.json](../../../artifacts/four-stream-20261017/real-site-health/host-probe-result.json)；同目录有公开规则文件和可复现脚本 `probe_public.py`。摘要只包含规则指纹、时间、状态码、耗时、公开标题、线路/集数和分层结论，不保存媒体 URL、响应正文、凭据或异常原文。脚本不得在没有新检查理由时重复执行。

下一步最小设备方案由集成负责人统一：使用现有应用真实选源入口或 QA-only 条目载入同一公开规则，明确选择上述 UBW 条目/第 1 集，只允许 1 个候选的 WebView 解析与首帧、35 秒预算，遇验证码立即停止并回手动，不重复尝试。不必为主机这三层重开模拟器；只有补应用解析/真实首帧时才需要设备。现有 feature_hub 的 `Target` / QA Playable 是合成 fixture，不能作为真实站点证据。若 Bangumi 简名与源完整标签不等，健康严格匹配应保守显示需要手动确认；可使用已明确同一作品的完整标签/别名，不修改生产匹配规则，不把 2006 条目当 UBW。

以上只覆盖该规则、该作品、该时刻；不证明其他番剧、其他集数或全站可用。
