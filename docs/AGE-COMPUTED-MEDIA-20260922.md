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
