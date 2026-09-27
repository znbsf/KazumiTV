# 来源与恢复可靠性阶段 · 2026-09-27

基线 `100580e3c9f1bdb2a461b49723103d8d9d1b48f1`；执行分支 `codex/playback-reliability-20260927`。本阶段未发现足以支持生产播放策略或规则推广修改的客户端缺陷，先交付定向诊断与恢复验收工具；设备结果和独立审查在下文按实际完成情况记录。没有更新版本、推送或发布。

## 实现与产物身份

工具提交 `98d0ddf772dd81b7173a42a40a2e293cfdf9b21a`：

- `RealTransportRecoveryRegression` 增加 `episode/source/process`。使用真实规则、目录、页面、媒体和生产 SourceScreen/PlaybackSessionScreen，不注入媒体地址、播放器错误或解析结果。先真实短播，再在自有模拟器受限网络下触发 IO 错误，启动重试，取消回原集表后手选新目标；检查取消后的迟到成功/播放器、新目标身份、独立进度和推进。手选其他集/其他源是用户从头选择，不冒充播放器内“同集保进度换源”的另一条路径。
- `process` 在恢复请求仍在途时请求主机 force-stop，主机读回旧 PID 消失、恢复网络并写带 checkpoint/PID/单调时钟的回执。`TransportProcessCompletion` 要求同一次新鲜回执和新 PID，从正常 LEANBACK Activity 启动，观察 10 秒无自动播放，再由真实最近观看→详情→继续动作检查同身份、原进度和推进。强制进程死亡不等于自然低内存回收；测试前挂载的是生产来源组件，不声称验证整个 TvApp 保存的 Activity 栈恢复。
- `RecordedEpisodeAudit` 可检查以前已观察到的 mutefun/mgnacg 同源节目页，输入文件限于应用外部目录的简单 JSON 文件名，URL 必须同 scheme/host/port 且无 user-info。响应中的挑战使测试停止。它不接受 akianime 或任意第三方解析地址，也不证明本轮搜索验证已通过。
- `tools/run-emulator-transport-recovery.ps1` 保留单调时钟、单会话过滤和网络 finally 恢复；`-ProcessDeath` 仅作用于模拟器和明确的 `process_kill_requested` 阶段。进程被杀时应用内 finally 不会执行，因此设备外层四存储检查点负责最终恢复。

生产源码与候选规则 JSON 均无变更。为验证当前源码重新构建的内部主 APK 是 `0.3.3/code53`，10,838,661 bytes，SHA-256 `856680B6BF5541976D37A375759CC551FBC5F414BF648B651CB58770F99F6387`；签名 SHA-256 `24f6145444bd07c2db4d3d355692e4dae3dc02cd632a933a9e03a27b9e32aa31`。这是内部测试构建，不是公开正式 APK `84E10D47…`，没有替换正式附件。

换集/换源最终测试 APK 为4,651,110 bytes，SHA-256 `A8349D4CC56BFFE291E75F43F6A1CC08FD84E3F576C17A61D0CB7741FF8F9A7C`。之后只补进程完成工具的控制栏唤出与去敏中间结果、以及独立审查指出的RecordedEpisodeAudit重定向后origin检查，测试包更新为 `4656538015113835E4C2F2B3A356386BEE67F4D107D1E08070E73C14D7EEE4CE`；主APK未重建。最终进程/夹具结果按这后一包身份记录；前期工具失败及mutefun诊断来自各自较早测试包。

## 固定规则与重点来源

2026-09-27 实时 `git ls-remote` 核对上游 KazumiRules HEAD 仍为 `0d85fc80ab6c208548d9ee9c9e81271b08ff7f39`。设备 `source-inventory` 的 17/17 均已安装、启用、与固定规范对象相等，没有导入或改写用户来源。当前上游 Kazumi HEAD 为 `cc8f67a129c5cc78e70ad38943a26a18adb3d102`，只读比较其 Android WebView fetch/XHR 清单及 video/src/iframe 发现实现；没有从该静态比较推导“原版本轮播放通过”。

| 重点项 | 本轮实际观察 | 规则差异/处理 | 仍未闭合与下一步条件 |
| --- | --- | --- | --- |
| dalvdm | 隔离候选普通搜索 HTTP200，生产检查明确要求人工图片验证，XPath结果0；未输入或提交。 | 沿用 `1.0-tv-candidate.2`；对固定规则的差异仍为候选名/版本、搜索与集表 XPath。未导入。 | 历史候选曾有6搜索/3线集表，但3线分别403、首帧后推进超时、404且0/3通过。本轮不把历史结果当当前播放。需用户在原页完成挑战，随后定向检验候选目录及有有效媒体的样本，才考虑推广。 |
| xfdmneo | 公开旧版入口候选的搜索 HTTP200，明确要求人工验证，XPath结果0；未输入或提交。 | 沿用 `1.1-tv-candidate.1`，公开旧版域名与现有验证码配置，与17源旧规则隔离；没有新上游版本可直接纳入。 | 旧版待人工正常交互；Next 站历史资料说明 JSON RPC/客户端渲染不同于旧 XPath，不能简单换域名，也未调用新RPC。取得实际目录/媒体后再验证迁移；本轮仍不可播放/未验。 |
| mgnacg 第5线 | 当前固定规则搜索要求人工验证；只读首页可到达，不代表目标第5线可用。 | 无规则更新或捕获补丁。 | 未取得当前目标媒体，不代解。历史1–4线短播可作替代参考，5线仍未通过；需原页人工验证后复现目标页、解析依赖与实际媒体差异。 |
| mutefun 第2线 | 当前搜索需人工验证。另对9月24日已观察到的同站第12集节目页做普通访问：HTTP200、未发现挑战，静态媒体候选0、iframe0；生产解析再次失败，WebView再次记录同站 SyntaxError。 | 无规则更新或播放器修复。主机只做同站页面/脚本的静态读取与 `node --check` 语法检查，不执行解密或站点代码。 | 两段内联脚本有语法错误；媒体配置 `r2/encrypt=3` 为不透明输入，同站播放器脚本可取得。脚本错误存在并不证明它是唯一根因；未获得原站正常播放成功对照，不能称客户端已修复或源已通过。历史第1线是替代参考；需正常浏览器媒体路径和同一页面的可复核对照。 |
| akianime 第2线 | 复核已有页面/同站脚本与现代内核失败记录；没有重新请求第三方解析页。 | 无规则或发现层修改。 | 既有直接第三方请求被自动审批拒绝仍生效，未换途径绕过。`Doki-…/xinpan` 不是原生媒体；第三方解析返回媒体与否仍未获证。历史第1线可作替代参考，2线继续保留未判定。 |

AGE3、baimao4/6、DM84/LMM1 的既有媒体连接失败/404及 ezdmw3 的 `null` 媒体，没有出现可判定的新客户端假设，本轮没有重复扫描。历史40线的30/10保持原样，不计算新“通过率”，不把归因或验证门槛写成播放成功。

## 真实恢复与受控验证

范围仅恢复中换目标及进程死亡；既有 A–G 没有重新全跑。

| 路径 | 实际断言及结果 | 范围 |
| --- | --- | --- |
| 恢复中换集 | PASS：baimao第12集实际IO2001，有限重试仍在途时Back回原集表；网络恢复后等待无迟到成功或播放器，手选第13集，真实目标从自己的进度推进至少5秒，额外观察旧请求不覆盖目标，选集“当前”身份正确。 | 生产组件、真实站点及媒体，模拟器传输限制；手选异集从头，不是整集或电视物理断网。 |
| 恢复中换源 | PASS：baimao第12集实际IO2001、在途重试取消回原集表；网络恢复后选择MXdm正常搜索/详情/第12集，手选目标从头并推进，历史目标键/作品身份和“当前”集正确，旧请求不覆盖新播放器。 | 这是错误页返回后手动选择新源。P1既有播放器内同集保进度换源证据保持原范围，本轮没有用此从头路径替代它。 |
| 恢复中进程死亡 | PASS：真实IO2001后在途恢复，主机 `am force-stop` 确认旧PID9707消失；checkpoint/PID/新鲜单调时钟回执匹配。新PID正常Launcher10秒无自动播放，用户明确最近观看→详情→继续，原56175ms记录续播并推进到65713ms，选集当前身份及origin正确。 | 显式force-stop和历史续播，非自然LMK或原Activity栈恢复。应用内finally无法在被杀进程执行，外层四存储restore/verify完成。 |
| 验证布局/提交、后台及原请求 | PASS：`verification` 的已知图片输入、按钮/异步脚本、假成功保护、取消和精确POST/Cookie；`verification-layout` 的图/输入/提交不重叠、网页操作Back恢复、HOME停止轮询和已知输入后的原搜索；`catalogue-verification` 的显式入口、Back同播放器、POST/Cookie、定时到期意图、后台不自动播放和旧对话框失效。 | 已知本地夹具，未解答或提交任何本轮真实人机挑战，不据此声称真实验证码全通过。 |

成功原始记录为 `final-episode/{test,host}.log`（checkpoint `transport-recovery-1790483230483`）、`final-source/{test,host}.log`（checkpoint `transport-recovery-1790483345343`）及 `final-process-menu/{test,host,completion}.log`（checkpoint `transport-recovery-1790483702720`）。进程轮instrumentation的 `Process crashed / CODE:0` 是明确host强制结束的预期结果，单独不算通过；只有PID消失回执和completion的完整PASS共同支撑结论。`fixture-*.log` 及 `candidate-structure-*.log` 记录夹具结果；两个候选均通过生产导入器/隔离仓库/9项文件边界检查，`imported=false/network=false/playback_unverified=true`。

所有恢复轮主动DNS/HTTP探测均关闭，播放器错误与媒体/网络请求均由生产路径实际产生；每轮host读回网络恢复与finally完成。设备侧私有JSONL保留时间线，不在公开输出打印URL。RecordedEpisodeAudit对manual-verification/timeout/failed也会正常结束instrumentation；此报告按JSONL的实际状态记录mutefun解析失败，没有按退出码冒称成功。

初轮失败保留：换集播放器已经到第13集5秒，但历史写入尚未达到同进度，测试读历史过早；等待历史后第二轮已完成目标推进及旧请求不覆盖，但末尾控制栏隐藏导致测试点“选集”超时；换源第一轮在编辑控件挂载前查找节点失败；进程死亡第一轮已确认旧PID消失，新入口无自动播放，但测试使用完整 HistoryEntry.episode 查找显示短集名的最近观看标签超时，修正短标签后又在末尾隐藏控制栏的“选集”检查超时。最后以遥控暂停/DPAD_UP唤出控件，才取得完整通过。均修正测试时机/标签/遥控操作，不改生产恢复逻辑，不删除失败记录。

## 环境、数据和证据

执行者独占 `Kazumi_Playback_Audit_API36 / emulator-5560`，Android16/WebView143.0.7499.24。启动前 ADB 无设备、5560/5561无监听和同名 AVD 进程。旧电视既有 `192.168.123.217:5555` 只试一次，Windows10061拒绝；没有取得本轮电视包或播放证据。

原5560主APK `9EFBBEFC…`、测试APK `77C4F013…` 均先保全。旧测试包即使标签 `p3four-` 仍只保存3存储：观察到 `stores=3` 后，先装当前支持四存储的测试包，再建立独立 `p3four-nextphase-full-20260927`，读回 `stores=4`，随后才安装内部主APK和执行测试；旧三存储检查点未被冒充四存储。未清 Cookie、应用数据或规则。每个普通恢复测试都有自身三存储finally，外层四存储检查点负责规则及强制杀进程路径。所有最终夹具后四存储verify unchanged；随后整体restore和verify再次相等。

**原主APK没有恢复，统筹已明确接受内部code53暂留于自有AVD的受限交还。** 原主APK是code52，保全件SHA256 `9EFBBEFCC5F2F42345F6F5CA4ED7B371A941621F1405828EF10FA0E1592E8FED`；内部主APK是code53，最终设备读回SHA256 `856680B6BF5541976D37A375759CC551FBC5F414BF648B651CB58770F99F6387`，与正式发布包 `84E10D47FC4DA031191371D41DB95ACB194AD5D690F141ED3BBA9EB7EDA5FAFB` 不同。普通 `adb install -r` 与 `-r -d` 均被 Android `INSTALL_FAILED_VERSION_DOWNGRADE` 拒绝，AVD读回 `ro.debuggable=0`。没有卸载、清应用数据、改原APK的versionCode或伪称原包已还。原测试APK已装回，最终设备侧SHA256 `77C4F0137061C3445C49840BC92F49129FA8C184AD3CAC004974393B4E9CCAFC` 等于保全件。统筹明确要求停止进一步降级尝试，遵守[AV方法](AV-ACCEPTANCE-20260927.md)第6项“不为回退而卸载或清数据”。

四存储整体恢复和核对记录为 `four-stores-restored-after-rejected-rollback.log` / `four-stores-verified-after-rejected-rollback.log`；原名称带original-main可能误导，已改为上述名称。接受交还后重启同一自有5560的最终核对 `four-stores-final-accepted-handoff.log` 再次读回 `user_data_checkpoint_unchanged stores=4 label=p3four-nextphase-full-20260927`。最终包hash记录为 `handoff-com.znbsf.kazumi.compose.tv-hash.txt` / `handoff-com.znbsf.kazumi.compose.tv.test-hash.txt`。网络最终 `network-final-handoff.txt` 读回download/upload均0 bits/s、delay均0ms；`audio-before.txt` 与 `audio-final-handoff.txt` 的STREAM_MUSIC状态块逐字段相等，均3/15、Muted=false、speaker。没有改宿主网络或音量。应用已force-stop，不留后台播放；自有AVD安全关闭，`handoff-closed.json` 记录avdExited=true、serialAbsent=true、userdataRetained=true，userdata-qemu.img保留。

主机原始证据根目录 `artifacts/next-phase-20260927`，Git忽略：逐次test/host日志、原包、四存储结果、当前规则快照、来源页面/脚本、console、failure截图只留本地。原始节目URL、Cookie、用户存储、页面、截图没有收入本报告或提交。没有录家庭环境、进行整集测试或补新AV声明。

229项单测/56报告零失败错误。初次完整Lint失败仅因新工作树 ignored `local.properties` 的Windows drive separator未转义；修正后强制重检成功，保留失败日志。release主APK、debug测试APK构建成功；后续只有测试工具增量时仅重构测试包，不重复生产整套。
