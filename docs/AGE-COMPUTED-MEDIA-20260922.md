# AGE 旧 WebView 已计算媒体地址诊断（2026-09-22）

## 范围

仅新增 instrumentation 诊断入口 `age-computed-media`，生产解析器不变。使用当前诊断保存的 AGE iframe、原集播放页 Referer、固定规则 UA，在独立 WebView 实例正常加载 30 秒；WebView 仍共享正常 provider profile。没有替换 Artplayer、执行解密脚本、修改规则或清除用户数据。

输入限应用外部目录、有限大小、已观察到的 iframe host 与 HTTPS 端口（443/8443）；直接 URL 参数被拒绝。通过自身数据属性描述符观察 `stray.url` 及可读的 `stray.ad.option.url`，不读取访问器。候选值和远端控制台文本仅存本地诊断目录，不纳入文档或 Git。

## 观察

主应用为 Preview 5；两端使用同一诊断测试 APK。旧电视是 WebView 66，现代模拟器是 WebView 143。

| 观察 | 旧电视 | 现代模拟器 |
| --- | --- | --- |
| 普通对象上的自身 URL 字符串属性 | 有 | 有 |
| 已计算 HTTP(S) 地址 | 有（144 字符） | 有（145 字符） |
| 常见媒体后缀 | 无 | 无 |
| 实际 Artplayer option.url 可观察 | 无 | 有 |
| option.url 与已计算地址相同 | 未验证 | 是 |
| 控制台错误类型 | SyntaxError | 无 |
| 本轮媒体探测 / 播放 | 未执行 | 未执行 |

日志：`artifacts/recovery-20260922/age-computed-tv-2.txt`、`age-computed-modern-2.txt`。最初诊断因未允许实际 iframe 8443 端口而在加载前被拒绝；不能将该次记录算作来源失败。

诊断字段 candidateCount 原定义要求媒体后缀，因此本轮为 0，不表示页面没有算出地址。现代端的播放器输入一致性支持继续调查，但不能替代旧电视实际播放、正确番剧/集数确认，也不能证明语法错误是所有失败的唯一原因。

## 后续边界

先以同次页面算出的原地址、原 UA / iframe Referer 做有界响应分类，再决定是否存在可安全复用的通用发现入口。当前生产 speculative 队列已可探测无后缀媒体；缺口在网页尚未实际请求地址时的发现。不得仅凭 HTTP、媒体 MIME 或唯一候选就认定当前集：广告、预加载或旧配置也可能是有效媒体。尚未添加生产环境全局对象扫描。

## 探测审批边界

原拟采用正常目标域 Cookie 和 iframe Referer 的探测没有执行：自动审批因可能外发会话材料而拒绝。检查 AppHttp 确认其 Cookie 按每次目标 URL 获取，没有手动复制来源站 Cookie；但这不等于本次请求已获审批。

改用更小范围的匿名诊断：`CookieJar.NO_COOKIES`，不发送 Referer、Origin 或认证头，不跟随重定向，不自动连接重试；仅发送 UA 和 Range，5 秒总时限，最多读取 1024 字节。此结果只表示候选端点匿名可读性，不等价于生产请求头、播放器正确集数或完整播放验证。

匿名探测第一轮（测试 APK SHA256 `3687b06f7a117929921ab83a7c43c66871a0c68b2db52a34c98666eedd73c179`）两端均遇到测试进程 `NoSuchMethodError`：debug 测试引用 `HttpText.exchange$app_debug`，设备上是 release 主包。此为 instrumentation 与生产包内部方法名称不一致，不是来源返回失败；本轮没有媒体响应结论。原始失败日志 `age-computed-tv-anonymous.txt`、`age-computed-modern-anonymous.txt` 保留。

## 匿名探测结果（2026-09-23 00:05）

修正测试内部方法依赖后，测试 APK SHA256 `57a33dbf2ba3d6ec2cdbb434d70ec01ca8b24d2d15fa05cc660fbd4c0cd268f2` 在两端完成：

- 旧电视：同次页面一个已计算 HTTP 候选、无后缀，仍有 SyntaxError、没有 Artplayer option；匿名 Range 响应 HTTP 206，MediaProbe 识别 `video/mp4`。
- 现代模拟器：一个已计算 HTTP 候选、无后缀，与实际 Artplayer option.url 一致，无控制台错误；匿名 Range 响应 HTTP 206，识别 `video/mp4`。
- 两端均无 Cookie / Referer / 认证头或重定向；测试正常退出，未执行播放器播放。日志 `age-computed-tv-anonymous-2.txt`、`age-computed-modern-anonymous-2.txt`。

结论限于页面已计算地址及匿名媒体可读性。旧电视的正确剧集首帧、短时推进、恢复和生产发现通路仍未验证，不改变全迁移未完成状态。

## 匿名解码短测（2026-09-23）

测试 APK SHA256 `bf013601bf65cfeb83b0c1bbd263739ad4f6129a4190c25e222c0b25fafebd95`，两端同次页面重新算出的地址均通过匿名 206/MP4 探测，随后独立 ExoPlayer 做首帧、5 秒推进、90 秒与 180 秒跳转、暂停稳定及继续推进，媒体时长均为 1,419,981 ms。播放静音，无 Cookie、Referer、认证头或重定向，不使用生产 NativePlayer / 历史存储。

两端保存的 180 秒画面经查看为相同动画场景。现代端当前 Artplayer 输入与读取字段一致，旧端仍有 SyntaxError、没有 Artplayer option。由此确认旧电视可解码同一播放页当前计算的媒体；尚未从片内集号独立确认“第12集”，不写作正确集数已验证，更不代表生产解析通路已经修复。

日志 `age-anonymous-play-tv.txt`、`age-anonymous-play-modern.txt`；截图 `age-frame-tv-180.png`、`age-frame-modern-180.png` 等位于本地 artifacts。诊断正常退出，没有整集测试；主应用保持 Preview5。

## 待验证生产候选

受限读取器只识别实际加载同一 Playpath 目录 `global.min.js` 与 `play.min.js` 的 PlayConfig/stray 驱动。配置、输入与地址仅读自身数据属性；普通对象/长度/HTTP(S)/无 userinfo 检查、现有 renderer 地址一致性约束。输入或驱动目录改变后本 document 永久拒绝，等待至少 8 秒，每文档最多给出一次候选。

候选仍走原 speculative 与 MIME 探测，不直接成为已确认媒体。为避免前面的无类型资源占满预算，总 speculative 预算仍为 8（Resource Timing 7，已知驱动配置 1），已确认 DOM/请求媒体保持优先。固定上游规则与来源存储不变。此段是候选实现说明，构建、双 WebView 负例和真实 AGE 线路结果需要另行记录后才能称为验证通过。

候选 APK SHA256 `e82456c66a3dc4a746428e8bd634f24f818b5544bb93c89d2bbaeac8de4131e9`：release 构建、204 项单元测试及 lint 通过。两种 WebView 的 28 项配置边界用例通过，包括 8 秒门槛、own-data getter 零调用、输入/目录变更永久拒绝、一次发出及 renderer 冲突。日志 `computed-config-tv-3.txt`、`computed-config-modern-3.txt`。

先前两轮 fixture 失败保留：第一次比较了不同 JSON 斜杠转义形式；第二次初始化表达式返回带 getter 的对象，引发 WebView 自动序列化。修正为解析 JSON 比较，并使初始化脚本返回 undefined，生产读取器未为这两项测试问题放宽条件。

首轮真实生产通路（同候选 `e82456c6…`）结果：现代端 AGE 第12集 5 线均完成短测；旧电视第1线完成正常解析、首帧、推进、拖动和暂停恢复，第2–5线仍在媒体发现阶段失败。日志 `computed-age-roads-tv.txt`、`computed-age-roads-modern.txt`。已不再只是匿名诊断首帧，但只关闭该样本第1线的发现缺口，不代表 AGE 5线、全站或迁移完成。

复核又发现饱和 collector 会截掉后方 iframe 的一次性 computed 结果，随后修复为独立保留1个 computed，再合入最多24项输出；resolver总预算仍为7+1。此收集器修复晚于上述候选，结果需按后续候选独立记账。

最终本地候选 SHA256 `2533088cdfd857ba55afbec05bd3167807d600565b89c4b6d28fcaf73c30076e`：修复 collector 后重新完成 release 构建、204 项单元测试（0失败/0错误）及 lint；28 项配置用例和实际 poll 饱和 iframe 集成例在 WebView66/143 均通过。日志 `computed-config-tv-saturated.txt`、`computed-config-modern-saturated.txt`。之前候选的通用 web-discovery 两端回归也通过（旧核 document_start 明确 SKIP，其余兼容分支通过）。本地候选含本地配置，不能上传公开。

最终同候选实际结果：旧电视第1线短测通过，第2–5线仍媒体发现失败；现代端5线全部短测通过。证据 `computed-final-age-tv.txt`、`computed-final-age-modern.txt`，两次测试均终止完成。结论是旧电视AGE从0/5推进到本样本1/5，未达到AGE全线或完整迁移验收。

后续第2线页面诊断已保存（`age-road2-page-modern.txt`）：200、5搜索结果、5线路、第12集页面一个iframe。其iframe仍同站点，但实际页面没有 PlayConfig/stray；存在顶层 Vurl 字符串与 `new Artplayer` 的 `url: Vurl` 引用，且静态 Vurl 本身是带媒体后缀的HTTP地址。原始HTML和地址仅本地 artifacts。后续应对照这种明确配置引用补通用能力，不能为此放宽当前驱动契约或泛扫所有字符串；当前未实现该后续能力。
