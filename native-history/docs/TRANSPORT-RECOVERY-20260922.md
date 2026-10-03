# 模拟器真实传输受限恢复 · 2026-09-22

状态：前两轮失败，随后两轮同一生产 APK 通过；恢复结果仍存在未解释差异，物理电视断网未验证。此项使用真实 baimao 搜索、集表、网页解析和媒体，没有注入播放器错误或替换解析结果；网络受限由 Google TV 模拟器控制台产生，不等同于物理电视断网。

测试先等待真实画面推进 5 秒，再将模拟器网络限制为 1000 bits/s、延迟 60000 ms，用实际快进键移到缓冲区外。要求发生真实 IO 播放错误，暂停后点击“重新加载”，受限网络下解析失败；恢复 unlimited/zero-delay 后点击“重新解析”，检查同集、原进度、暂停状态和显式继续推进。

## 执行结果

| 轮次 | 本地候选 APK SHA256 | 观测 |
| --- | --- | --- |
| 1 | `14f57e35b624bc98c02808803f4d1749df156bc5363154a0822fbe429cdd6b0b` | IO 错误 2001，暂停目标 57325 ms；恢复重试等待失败，旧诊断不足以确定后续阶段 |
| 2 | `ab83f4b46af8852848d7ebc1bd61de0caab9c86c7871c695fa5d0148bf57a65f` | IO 错误 2001，暂停目标 36453 ms；恢复后重新解析再次失败，未创建新播放器 |
| 3 | 同第 2 轮生产包；仅测试包增加可选诊断 | IO 错误 2001，暂停目标 57880 ms；首次恢复重试成功，新播放器保留暂停进度，显式播放推进 5 秒，同为第 12 集 |
| 4 | 同第 3 轮 | IO 错误 2001，暂停目标 36638 ms；首次恢复重试成功，暂停/进度/新播放器/显式推进/同集检查均通过 |

第二轮每 5 秒记录播放器存在性、进度、暂停意图、帧数和解析按钮状态。恢复后约 71–136 秒持续 `playerPresent=false`、`hasReparse=true`，现场截图显示“网页加载：连接或证书错误（-2）”。因此失败发生在 WebView 主页面域名解析阶段，不能归因于恢复后进度或暂停首帧检查。错误文案将多个网络错误合并描述，此处 -2 对应 host lookup。

随后单独执行同源诊断：搜索 HTTP 200 / 11 条结果、集表 6 线、播放页 HTTP 200，WebView 解析得到 HLS。这只能说明结束后的新请求可用，不能证明原会话恢复成功，也不能证实 DNS 负缓存就是根因。

四轮结束均恢复三个用户数据存储并核对相等，host finally 恢复网络并读回 unlimited / 0 ms。未清除 Cookie、未修改证书策略、未进行整集测试。公开 Preview 4 不包含本轮本地修复。

第 3–4 轮开启 `delayedRetry=true`：仅当首次重试再次显示解析失败时，等待 15 秒、观测原播放页 HttpText 请求，再明确点击一次重试。两轮均在首次重试成功，`recovery_attempts=1`，延迟分支和其中的 HttpText 诊断实际未触发。不能据此声称延迟重试修复了问题，也未证实 DNS 缓存假设。生产代码在第 2–4 轮之间没有变化。

## 可复现入口与下一步

测试入口 `real-transport-recovery`；主机协调脚本 `tools/run-emulator-transport-recovery.ps1` 仅接受 emulator serial，开始前要求正常网络，所有退出路径恢复网络。先启动 instrumentation，再启动脚本；不得并发启动同设备的另一测试。

本地证据位于 `artifacts/recovery-20260922`：`transport-modern.txt`、`transport-host.txt`、`transport-modern-2.txt`、`transport-host-2.txt`、`transport-live.png`、`post-transport-baimao-modern.txt`。设备另存每阶段安全诊断与失败截图。

后续通过记录为 `transport-modern-3.txt` / `transport-host-3.txt` 和 `transport-modern-4.txt` / `transport-host-4.txt`。保留失败记录，不以两次通过覆盖前两次失败。

下一步在同一次恢复中分别观测目标的 Java DNS、HttpText 与 WebView 结果，并记录一次延迟后的明确重试；继续保留原进度、暂停、新播放器、显式推进和同集断言。不得将延长等待、后续单独解析成功或受控恢复结果写成此项通过。

## 待执行的阶段诊断（2026-09-23 测试代码）

`real-transport-recovery` 默认 `phaseDiagnostics=false`，不新增主动 DNS/HTTP 请求。`delayedRetry=true` 仍只在首次恢复重试失败后等待 15 秒并明确点击第二次；首次成功写入 `delayed_retry_not_triggered`，不能当作延迟重试有效的证据。建议主执行者用相同 APK、规则输入和模拟器配置分别跑基线轮（`-e delayedRetry true -e phaseDiagnostics false`）及诊断轮（`-e delayedRetry true -e phaseDiagnostics true`），保留各轮失败，不交叉合并通过结论。

每轮仍先启动 instrumentation 的 `-e mode real-transport-recovery`，然后在另一终端运行 `tools/run-emulator-transport-recovery.ps1 -Adb <adb绝对路径> -Serial <重新枚举的emulator序列号> -OutputDirectory <已存在的本地证据目录>`。只由原会话主执行者运行；脚本要求初始 unlimited/0 ms，最终 `finally` 恢复网络。不要在此工作树运行设备操作。仪器输出的 `checkpoint` 对应设备 app-specific 目录下的 `stages.jsonl`、`state.jsonl` 和失败截图；截图按私有证据处理。

主执行者在两终端分别运行下列命令；`$adb`、`$serial`、`$out` 需先设为本机已确认的绝对路径、重新枚举的模拟器序列号和已存在的证据目录。诊断轮仅将 `false` 换成 `true`，每轮使用新的输出文件。

```powershell
# 终端 1，先启动并保持到仪器完成
& $adb -s $serial shell am instrument -w -e mode real-transport-recovery -e delayedRetry true -e phaseDiagnostics false 'com.znbsf.kazumi.compose.tv.test/org.kazumi.tv.TvNetworkInstrumentation'
# 终端 2，随后启动主机协调
& .\tools\run-emulator-transport-recovery.ps1 -Adb $adb -Serial $serial -OutputDirectory $out
```

阶段记录使用设备 `elapsedRealtimeMs`、恢复尝试序号和阶段。主机在 `speed full`、`delay none` 和状态读回确认后读取 `/proc/uptime`，输出 `network_restore_confirmed.deviceElapsedRealtimeMs`，并随 `restored:<毫秒>` 命令传给测试的 `restoreCompletedDeviceMs`；这是恢复确认完成时点的设备单调时钟上界，存在 ADB 读取延迟。`restoreObservedDeviceMs` 是测试读到该命令的时点，可对照随后探测、WebView 界面错误和播放器状态。主机也输出 Stopwatch ticks/frequency，不能直接拿主机 ticks 与设备毫秒相减。

仅诊断轮在同一次会话已选中的原集播放页、每次恢复尝试最多执行一次 Java DNS（等待上限 3 秒）和一次 `HttpText.pageAsync`（等待上限 8 秒），只输出成功/失败类别、HTTP 状态及耗时，不输出解析地址、URL、Cookie、请求体、响应正文、凭证或原始异常。DNS 超时会取消 Future 并关闭 daemon executor，但系统解析可能仍短暂占用线程。`activeProbesEnabled` 和 `dnsProbesExecuted`/`httpProbesExecuted` 区分开关与实际执行；探测会改变 DNS/HTTP 缓存、连接与点击时序。诊断轮通过只能说明该轮通过，不能直接证明生产恢复已修复。

`webErrorCode` 只从生产界面上可见的“网页加载”错误提取；`webFrame=unavailable_from_production_ui`、`webNavigationGeneration=null` 明示目前不能把该错误可靠归到主框架或 iframe 的某次导航。若同会话结果显示这个区分是归因所必需，下一步建议在 `WebMediaResolver` 的 `onPageStarted`、`onReceivedError`、`onReceivedHttpError` 增加安全的结构化测试观测口，仅输出解析尝试/候选编号、主框架标记、导航代次、错误码和设备单调时间，不含 URL 或页面内容；本包没有改生产代码或重试策略。

期望失败证据：网络受限确实触发真实播放器 IO 错误和解析失败，恢复后首次重试若失败，保留其界面错误码及同一恢复的 DNS/HttpText 时间关系；启用延迟重试时只允许第二次明确点击。期望通过证据：同剧同集、新播放器、目标进度容差内保持暂停，明确播放后推进 5 秒，最后用户数据恢复相等。`NOT_TRIGGERED_*` 和单独的 DNS/HTTP 成功都不是播放恢复通过；模拟器结果不关闭物理电视断网待验项。
