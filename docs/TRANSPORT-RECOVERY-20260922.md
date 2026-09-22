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
